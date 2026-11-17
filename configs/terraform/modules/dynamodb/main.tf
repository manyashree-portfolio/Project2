terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      configuration_aliases = [aws.primary, aws.secondary]
    }
  }
}

locals {
  tables = toset(["paysecure-idempotency", "paysecure-sessions"])
}

# Global Tables (version 2019.11.21). Writes go to Mumbai during normal operation;
# Hyderabad takes writes only after failover, so last-writer-wins conflicts are avoided.
resource "aws_dynamodb_table" "this" {
  for_each         = local.tables
  provider         = aws.primary
  name             = each.key
  billing_mode     = "PROVISIONED"
  read_capacity    = var.capacity[each.key].read
  write_capacity   = var.capacity[each.key].write
  hash_key         = "pk"
  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"

  attribute {
    name = "pk"
    type = "S"
  }

  ttl {
    attribute_name = "expires_at"
    enabled        = true
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = var.primary_kms_key_arn
  }

  replica {
    region_name            = "ap-south-2"
    kms_key_arn            = var.replica_kms_key_arn
    point_in_time_recovery = true
  }

  lifecycle {
    # Autoscaling manages capacity after creation
    ignore_changes = [read_capacity, write_capacity]
  }
}

# Provisioned Global Tables need write autoscaling in every region.
resource "aws_appautoscaling_target" "write_primary" {
  for_each           = local.tables
  provider           = aws.primary
  service_namespace  = "dynamodb"
  resource_id        = "table/${each.key}"
  scalable_dimension = "dynamodb:table:WriteCapacityUnits"
  min_capacity       = var.capacity[each.key].write
  max_capacity       = var.capacity[each.key].write * 3
  depends_on         = [aws_dynamodb_table.this]
}

resource "aws_appautoscaling_target" "write_secondary" {
  for_each           = local.tables
  provider           = aws.secondary
  service_namespace  = "dynamodb"
  resource_id        = "table/${each.key}"
  scalable_dimension = "dynamodb:table:WriteCapacityUnits"
  min_capacity       = var.capacity[each.key].write
  max_capacity       = var.capacity[each.key].write * 3
  depends_on         = [aws_dynamodb_table.this]
}

resource "aws_appautoscaling_policy" "write_primary" {
  for_each           = local.tables
  provider           = aws.primary
  name               = "${each.key}-write-70"
  policy_type        = "TargetTrackingScaling"
  service_namespace  = aws_appautoscaling_target.write_primary[each.key].service_namespace
  resource_id        = aws_appautoscaling_target.write_primary[each.key].resource_id
  scalable_dimension = aws_appautoscaling_target.write_primary[each.key].scalable_dimension
  target_tracking_scaling_policy_configuration {
    target_value = 70
    predefined_metric_specification {
      predefined_metric_type = "DynamoDBWriteCapacityUtilization"
    }
  }
}

resource "aws_appautoscaling_policy" "write_secondary" {
  for_each           = local.tables
  provider           = aws.secondary
  name               = "${each.key}-write-70"
  policy_type        = "TargetTrackingScaling"
  service_namespace  = aws_appautoscaling_target.write_secondary[each.key].service_namespace
  resource_id        = aws_appautoscaling_target.write_secondary[each.key].resource_id
  scalable_dimension = aws_appautoscaling_target.write_secondary[each.key].scalable_dimension
  target_tracking_scaling_policy_configuration {
    target_value = 70
    predefined_metric_specification {
      predefined_metric_type = "DynamoDBWriteCapacityUtilization"
    }
  }
}

# Replication latency above 1,000 ms for 3 consecutive checks = P1 (replication-strategy.md Section 10).
resource "aws_cloudwatch_metric_alarm" "replication_latency" {
  for_each            = local.tables
  provider            = aws.primary
  alarm_name          = "${each.key}-replication-latency-p1"
  alarm_description   = "P1: DynamoDB global table replication latency above 1,000 ms"
  namespace           = "AWS/DynamoDB"
  metric_name         = "ReplicationLatency"
  dimensions          = { TableName = each.key, ReceivingRegion = "ap-south-2" }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 3
  datapoints_to_alarm = 3
  threshold           = 1000
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [var.alarm_topic_arn_primary]
  ok_actions          = [var.alarm_topic_arn_primary]
  depends_on          = [aws_dynamodb_table.this]
}

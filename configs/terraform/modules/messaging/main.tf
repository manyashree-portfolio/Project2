terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      configuration_aliases = [aws.primary, aws.secondary]
    }
  }
}

# RB-04 Path R: terraform -chdir=configs/terraform/envs/prod apply -target=module.messaging -var msk_cluster_name=paysecure-prod-v2

resource "aws_security_group" "primary" {
  provider    = aws.primary
  name_prefix = "paysecure-msk-primary-"
  vpc_id      = var.primary_vpc_id
  ingress {
    from_port   = 9098
    to_port     = 9098
    protocol    = "tcp"
    cidr_blocks = var.primary_allowed_cidrs
  }
}

resource "aws_security_group" "secondary" {
  provider    = aws.secondary
  name_prefix = "paysecure-msk-secondary-"
  vpc_id      = var.secondary_vpc_id
  ingress {
    from_port   = 9098
    to_port     = 9098
    protocol    = "tcp"
    cidr_blocks = var.secondary_allowed_cidrs
  }
}

resource "aws_cloudwatch_log_group" "primary" {
  provider          = aws.primary
  name              = "/aws/msk/${var.primary_cluster_name}"
  retention_in_days = 180 # CERT-In: logs kept at least 180 days in India
}

resource "aws_cloudwatch_log_group" "secondary" {
  provider          = aws.secondary
  name              = "/aws/msk/${var.secondary_cluster_name}"
  retention_in_days = 180
}

resource "aws_msk_cluster" "primary" {
  provider               = aws.primary
  cluster_name           = var.primary_cluster_name
  kafka_version          = var.kafka_version
  number_of_broker_nodes = var.broker_count
  enhanced_monitoring    = "PER_TOPIC_PER_BROKER"

  broker_node_group_info {
    instance_type   = var.instance_type
    client_subnets  = var.primary_subnet_ids
    security_groups = [aws_security_group.primary.id]
    storage_info {
      ebs_storage_info {
        volume_size = var.volume_size_gb
      }
    }
  }

  client_authentication {
    sasl {
      iam = true # required by MSK Replicator
    }
  }

  encryption_info {
    encryption_at_rest_kms_key_arn = var.primary_kms_key_arn
    encryption_in_transit {
      client_broker = "TLS"
      in_cluster    = true
    }
  }

  logging_info {
    broker_logs {
      cloudwatch_logs {
        enabled   = true
        log_group = aws_cloudwatch_log_group.primary.name
      }
    }
  }
}

resource "aws_msk_cluster" "secondary" {
  provider               = aws.secondary
  cluster_name           = var.secondary_cluster_name
  kafka_version          = var.kafka_version
  number_of_broker_nodes = var.broker_count
  enhanced_monitoring    = "PER_TOPIC_PER_BROKER"

  broker_node_group_info {
    instance_type   = var.instance_type
    client_subnets  = var.secondary_subnet_ids
    security_groups = [aws_security_group.secondary.id]
    storage_info {
      ebs_storage_info {
        volume_size = var.volume_size_gb
      }
    }
  }

  client_authentication {
    sasl {
      iam = true
    }
  }

  encryption_info {
    encryption_at_rest_kms_key_arn = var.secondary_kms_key_arn
    encryption_in_transit {
      client_broker = "TLS"
      in_cluster    = true
    }
  }

  logging_info {
    broker_logs {
      cloudwatch_logs {
        enabled   = true
        log_group = aws_cloudwatch_log_group.secondary.name
      }
    }
  }
}

data "aws_iam_policy_document" "replicator_trust" {
  provider = aws.secondary
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["kafka.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "replicator" {
  provider = aws.secondary
  statement {
    sid     = "ClusterAccess"
    actions = ["kafka-cluster:Connect", "kafka-cluster:DescribeCluster", "kafka-cluster:AlterCluster", "kafka-cluster:DescribeTopic", "kafka-cluster:CreateTopic", "kafka-cluster:AlterTopic", "kafka-cluster:WriteData", "kafka-cluster:ReadData", "kafka-cluster:AlterGroup", "kafka-cluster:DescribeGroup"]
    # Scope down to the two clusters' topics and groups once the topic list is final.
    resources = [aws_msk_cluster.primary.arn, aws_msk_cluster.secondary.arn, "${replace(aws_msk_cluster.primary.arn, ":cluster/", ":topic/")}/*", "${replace(aws_msk_cluster.secondary.arn, ":cluster/", ":topic/")}/*", "${replace(aws_msk_cluster.primary.arn, ":cluster/", ":group/")}/*", "${replace(aws_msk_cluster.secondary.arn, ":cluster/", ":group/")}/*"]
  }
  statement {
    sid       = "Network"
    actions   = ["ec2:CreateNetworkInterface", "ec2:DescribeNetworkInterfaces", "ec2:DescribeSubnets", "ec2:DescribeSecurityGroups", "ec2:DeleteNetworkInterface"]
    resources = ["*"]
  }
}

resource "aws_iam_role" "replicator" {
  provider           = aws.secondary
  name               = "paysecure-msk-replicator"
  assume_role_policy = data.aws_iam_policy_document.replicator_trust.json
}

resource "aws_iam_role_policy" "replicator" {
  provider = aws.secondary
  name     = "replicator"
  role     = aws_iam_role.replicator.id
  policy   = data.aws_iam_policy_document.replicator.json
}

# Mumbai -> Hyderabad, topic names kept identical, consumer-group offsets synchronised.
resource "aws_msk_replicator" "this" {
  provider                   = aws.secondary
  replicator_name            = "paysecure-replicator"
  description                = "Mumbai to Hyderabad topic and consumer-group replication"
  service_execution_role_arn = aws_iam_role.replicator.arn

  kafka_cluster {
    amazon_msk_cluster {
      msk_cluster_arn = aws_msk_cluster.primary.arn
    }
    vpc_config {
      subnet_ids          = var.primary_subnet_ids
      security_groups_ids = [aws_security_group.primary.id]
    }
  }

  kafka_cluster {
    amazon_msk_cluster {
      msk_cluster_arn = aws_msk_cluster.secondary.arn
    }
    vpc_config {
      subnet_ids          = var.secondary_subnet_ids
      security_groups_ids = [aws_security_group.secondary.id]
    }
  }

  replication_info_list {
    source_kafka_cluster_arn = aws_msk_cluster.primary.arn
    target_kafka_cluster_arn = aws_msk_cluster.secondary.arn
    target_compression_type  = "NONE"

    topic_replication {
      topics_to_replicate                  = [".*"]
      copy_topic_configurations            = true
      copy_access_control_lists_for_topics = true
      detect_and_copy_new_topics           = true
      starting_position {
        type = "EARLIEST"
      }
      topic_name_configuration {
        type = "IDENTICAL"
      }
    }

    consumer_group_replication {
      consumer_groups_to_replicate        = [".*"]
      detect_and_copy_new_consumer_groups = true
      synchronise_consumer_group_offsets  = true
    }
  }
}

# Replicator lag above 10,000 messages for 5 minutes = P2 (replication-strategy.md Section 10).
resource "aws_cloudwatch_metric_alarm" "replicator_lag" {
  provider            = aws.secondary
  alarm_name          = "paysecure-msk-replicator-lag-p2"
  alarm_description   = "P2: MSK Replicator message lag above 10,000"
  namespace           = "AWS/Kafka"
  metric_name         = "MessageLag"
  dimensions          = { "Replicator Name" = aws_msk_replicator.this.replicator_name }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 5
  datapoints_to_alarm = 5
  threshold           = 10000
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "breaching"
  alarm_actions       = [var.alarm_topic_arn_dr]
  ok_actions          = [var.alarm_topic_arn_dr]
}

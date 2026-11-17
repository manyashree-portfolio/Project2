terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      configuration_aliases = [aws.primary, aws.secondary]
    }
  }
}

# Alert topics in both regions. Alert payloads carry alarm name, severity and resource ID only:
# PagerDuty is a third-party processor outside the India boundary (docs/07-data-sovereignty).
resource "aws_sns_topic" "primary" {
  provider          = aws.primary
  name              = "paysecure-alerts"
  kms_master_key_id = var.primary_kms_key_id
}

resource "aws_sns_topic" "dr" {
  provider          = aws.secondary
  name              = "paysecure-alerts"
  kms_master_key_id = var.secondary_kms_key_id
}

resource "aws_sns_topic_subscription" "pagerduty_primary" {
  count                  = var.pagerduty_integration_url == "" ? 0 : 1
  provider               = aws.primary
  topic_arn              = aws_sns_topic.primary.arn
  protocol               = "https"
  endpoint               = var.pagerduty_integration_url
  endpoint_auto_confirms = true
}

resource "aws_sns_topic_subscription" "pagerduty_dr" {
  count                  = var.pagerduty_integration_url == "" ? 0 : 1
  provider               = aws.secondary
  topic_arn              = aws_sns_topic.dr.arn
  protocol               = "https"
  endpoint               = var.pagerduty_integration_url
  endpoint_auto_confirms = true
}

# Payment success rate below 99.5% for 2 minutes = P1 (docs section A5 thresholds).
# This alarm is also the third child of the Route 53 calculated health check (modules/dns).
resource "aws_cloudwatch_metric_alarm" "payment_success_rate" {
  provider            = aws.primary
  alarm_name          = "paysecure-payment-api-success-rate-below-99-5"
  alarm_description   = "P1: payment API success rate (2xx/total) below 99.5% for 2 minutes"
  namespace           = "PaySecure/PaymentAPI"
  metric_name         = "payment_api_success_rate_2xx_over_total"
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 2
  datapoints_to_alarm = 2
  threshold           = 99.5
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "breaching"
  alarm_actions       = [aws_sns_topic.primary.arn]
  ok_actions          = [aws_sns_topic.primary.arn]
}

# Payment P99 latency above the 300 ms NPCI ceiling for 5 minutes = P2
resource "aws_cloudwatch_metric_alarm" "payment_latency" {
  provider            = aws.primary
  alarm_name          = "paysecure-payment-api-p99-latency-above-300ms"
  alarm_description   = "P2: transaction P99 latency above 300 ms for 5 minutes"
  namespace           = "PaySecure/PaymentAPI"
  metric_name         = "payment_api_latency_p99_ms"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 5
  datapoints_to_alarm = 5
  threshold           = 300
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.primary.arn]
}

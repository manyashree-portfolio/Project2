output "alarm_topic_arn_primary" {
  description = "SNS topic ARN in ap-south-1"
  value       = aws_sns_topic.primary.arn
}

output "alarm_topic_arn_dr" {
  description = "SNS topic ARN in ap-south-2"
  value       = aws_sns_topic.dr.arn
}

output "success_rate_alarm_name" {
  description = "Name of the payment success-rate alarm used by the Route 53 health check"
  value       = aws_cloudwatch_metric_alarm.payment_success_rate.alarm_name
}

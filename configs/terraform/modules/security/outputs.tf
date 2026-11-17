output "primary_key_arns" {
  description = "Map of key purpose to multi-Region primary key ARN (ap-south-1)"
  value       = { for k, v in aws_kms_key.primary : k => v.arn }
}

output "replica_key_arns" {
  description = "Map of key purpose to replica key ARN (ap-south-2)"
  value       = { for k, v in aws_kms_replica_key.replica : k => v.arn }
}

output "web_acl_arn" {
  description = "ARN of the regional payment API web ACL"
  value       = aws_wafv2_web_acl.api.arn
}

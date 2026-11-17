variable "primary_kms_key_arn" {
  description = "ARN of the Mumbai KMS key used for encryption"
  type        = string
}
variable "secondary_kms_key_arn" {
  description = "ARN of the Hyderabad KMS replica key used for encryption"
  type        = string
}
variable "alarm_topic_arn_primary" {
  description = "SNS topic ARN in ap-south-1 that receives alarms"
  type        = string
}

variable "audit_retention_years" {
  description = "Object Lock retention on audit buckets (7 years, matching the evidence retention in RB-06 and RB-11)"
  type        = number
  default     = 7
}

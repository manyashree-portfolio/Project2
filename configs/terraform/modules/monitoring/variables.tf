variable "primary_kms_key_id" {
  description = "KMS key ID or alias used to encrypt the Mumbai alert topic"
  type        = string
}

variable "secondary_kms_key_id" {
  description = "KMS key ID or alias used to encrypt the Hyderabad alert topic"
  type        = string
}

variable "pagerduty_integration_url" {
  description = "PagerDuty events integration URL. Leave empty to create topics without a subscription"
  type        = string
  default     = ""
  sensitive   = true
}

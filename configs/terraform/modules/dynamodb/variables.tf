variable "primary_kms_key_arn" {
  description = "ARN of the Mumbai KMS key used for encryption"
  type        = string
}
variable "replica_kms_key_arn" {
  description = "ARN of the Hyderabad KMS replica key"
  type        = string
}
variable "alarm_topic_arn_primary" {
  description = "SNS topic ARN in ap-south-1 that receives alarms"
  type        = string
}

variable "capacity" {
  description = "Provisioned units per table. Total 10,000 RCU / 5,000 WCU as in current-architecture.md; the split between the two tables is assumed"
  type        = map(object({ read = number, write = number }))
  default = {
    "paysecure-idempotency" = { read = 6000, write = 3000 }
    "paysecure-sessions"    = { read = 4000, write = 2000 }
  }
}

variable "target_ids" {
  description = "OU or account IDs of the PAYMENT accounts the India-only SCP attaches to (do not include operations accounts)"
  type        = list(string)
}

variable "allowed_regions" {
  description = "Allowed regions"
  type        = list(string)
  default     = ["ap-south-1", "ap-south-2"]
}

variable "operations_account_ids" {
  description = "Accounts that may hold the redacted operational copy in ap-southeast-1 (never payment accounts)"
  type        = list(string)
  default     = []
}

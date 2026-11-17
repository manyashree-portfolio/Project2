variable "keys" {
  description = "Key purpose => alias. cde protects cardholder data; data protects everything else (RB-06 improvement: separate keys limit blast radius)"
  type        = map(string)
  default = {
    cde  = "alias/paysecure-cde"
    data = "alias/paysecure-data"
  }
}

variable "merchant_ip_cidrs" {
  description = "Merchant server IPs for the WAF allow-list (RB-07). Placeholders only in examples"
  type        = list(string)
  default     = []
}

variable "alb_arn" {
  description = "ARN of the public ALB to protect. Empty = do not associate the web ACL or Shield"
  type        = string
  default     = ""
}

variable "enable_shield_advanced" {
  description = "Create a Shield Advanced protection for the ALB (requires an active Shield Advanced subscription)"
  type        = bool
  default     = false
}

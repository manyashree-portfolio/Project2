variable "zone_id" {
  description = "Route 53 hosted zone ID"
  type        = string
}
variable "mum_alb_dns" {
  description = "DNS name of the Mumbai ALB"
  type        = string
}
variable "hyd_alb_dns" {
  description = "DNS name of the Hyderabad ALB"
  type        = string
}
variable "success_rate_alarm_name" {
  description = "Name of the CloudWatch success-rate alarm used as a health check child"
  type        = string
}

variable "ttl_seconds" {
  description = "30 s normally; lowered to 10 s 24 hours before drills (annual-drill-plan.md)"
  type        = number
  default     = 30
}

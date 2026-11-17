variable "primary_vpc_id" {
  description = "ID of the existing Mumbai VPC"
  type        = string
}
variable "primary_subnet_ids" {
  description = "Private subnet IDs in ap-south-1"
  type        = list(string)
}
variable "primary_allowed_cidrs" {
  description = "CIDR blocks allowed to reach the Mumbai service port"
  type        = list(string)
}
variable "secondary_vpc_id" {
  description = "ID of the Hyderabad VPC"
  type        = string
}
variable "secondary_subnet_ids" {
  description = "Private subnet IDs in ap-south-2"
  type        = list(string)
}
variable "secondary_allowed_cidrs" {
  description = "CIDR blocks allowed to reach the Hyderabad service port"
  type        = list(string)
}
variable "primary_kms_key_arn" {
  description = "ARN of the Mumbai KMS key used for encryption"
  type        = string
}
variable "secondary_kms_key_arn" {
  description = "ARN of the Hyderabad KMS replica key used for encryption"
  type        = string
}
variable "master_username" {
  description = "Aurora master user name (the password is managed by Secrets Manager)"
  type        = string
}

variable "instance_class" {
  description = "Instance class"
  type        = string
  default     = "db.r6g.2xlarge"
}

variable "dr_instance_count" {
  description = "Dr instance count"
  type        = number
  default     = 2
}

variable "alarm_topic_arn_dr" {
  description = "SNS topic ARN in ap-south-2 that receives alarms"
  type        = string
}

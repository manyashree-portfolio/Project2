variable "primary_cluster_name" {
  description = "Name of the Mumbai MSK cluster"
  type        = string
}
variable "secondary_cluster_name" {
  description = "Name of the Hyderabad MSK cluster"
  type        = string
}
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
variable "alarm_topic_arn_dr" {
  description = "SNS topic ARN in ap-south-2 that receives alarms"
  type        = string
}

variable "instance_type" {
  description = "Instance type"
  type        = string
  default     = "kafka.m5.2xlarge"
}

variable "kafka_version" {
  description = "Use the version the Mumbai cluster runs (assumed)"
  type        = string
  default     = "3.6.0"
}

variable "broker_count" {
  description = "6 brokers, as in current-architecture.md"
  type        = number
  default     = 6
}

variable "volume_size_gb" {
  description = "Per-broker EBS size sized for 7-day retention (assumed)"
  type        = number
  default     = 2000
}

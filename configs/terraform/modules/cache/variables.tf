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

variable "node_type" {
  description = "Node type"
  type        = string
  default     = "cache.r6g.xlarge"
}

variable "shards" {
  description = "Cluster-mode node groups (assumed)"
  type        = number
  default     = 3
}

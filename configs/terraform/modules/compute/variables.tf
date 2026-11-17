variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}
variable "cluster_version" {
  description = "Kubernetes version of the EKS cluster"
  type        = string
}
variable "vpc_id" {
  description = "ID of the VPC"
  type        = string
}
variable "subnet_ids" {
  description = "Subnet IDs"
  type        = list(string)
}
variable "node_instance_type" {
  description = "EC2 instance type of the worker nodes"
  type        = string
}
variable "baseline_nodes" {
  description = "Number of worker nodes provisioned at all times"
  type        = number
}
variable "failover_increment_nodes" {
  description = "Extra nodes covered by On-Demand Capacity Reservations"
  type        = number
}
variable "kms_key_arn" {
  description = "ARN of the KMS key for secrets encryption"
  type        = string
}

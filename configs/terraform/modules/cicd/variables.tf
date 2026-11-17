variable "runner_ami" {
  description = "AMI ID of the clean pipeline runner image"
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
variable "github_repo" {
  description = "GitHub ORG/REPO allowed to assume the deploy role through OIDC"
  type        = string
}

variable "instance_type" {
  description = "Instance type"
  type        = string
  default     = "m6i.xlarge"
}

variable "runner_count" {
  description = "Runner count"
  type        = number
  default     = 2
}

variable "egress_cidrs" {
  description = "Allowed HTTPS destinations. Replace the default with the VPC endpoint and registry ranges you actually use"
  type        = list(string)
  default     = ["10.0.0.0/16"]
}

variable "github_oidc_thumbprints" {
  description = "Verify the current GitHub OIDC thumbprint before use"
  type        = list(string)
  default     = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

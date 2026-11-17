variable "environment" {
  description = "Environment name used in tags"
  type        = string
  default     = "prod"
}

variable "allowed_account_ids" {
  description = "AWS account IDs this configuration may run against"
  type        = list(string)
}

# ---- Existing Mumbai network (already deployed) ----
variable "primary_vpc_id" {
  description = "ID of the existing Mumbai VPC"
  type        = string
}

variable "primary_vpc_cidr" {
  description = "CIDR block of the Mumbai VPC"
  type        = string
  default     = "10.0.0.0/16" # assumed, see current-architecture.md
}

variable "primary_private_subnet_ids" {
  description = "Private subnets in ap-south-1a/b/c"
  type        = list(string)
}

# ---- Hyderabad network (new) ----
variable "dr_vpc_cidr" {
  description = "Must not overlap the Mumbai VPC (assumed value)"
  type        = string
  default     = "10.1.0.0/16"
}

variable "transit_gateway_amazon_side_asn" {
  description = "Transit gateway amazon side asn"
  type        = number
  default     = 64513
}

# ---- Data stores (assumed sizes, see cost-model.xlsx) ----
variable "db_master_username" {
  description = "Db master username"
  type        = string
  default     = "paysecure_admin"
}

variable "aurora_instance_class" {
  description = "Aurora instance class"
  type        = string
  default     = "db.r6g.2xlarge"
}

variable "aurora_dr_instance_count" {
  description = "Instances in the Hyderabad secondary cluster (cost optimisation lever: 2 -> 1)"
  type        = number
  default     = 2
}

variable "redis_node_type" {
  description = "Redis node type"
  type        = string
  default     = "cache.r6g.xlarge" # assumed
}

# ---- Messaging (RB-04 passes -var msk_cluster_name=...) ----
variable "msk_cluster_name" {
  description = "Msk cluster name"
  type        = string
  default     = "paysecure-prod"
}

variable "msk_instance_type" {
  description = "Msk instance type"
  type        = string
  default     = "kafka.m5.2xlarge" # assumed
}

# ---- Compute ----
variable "eks_cluster_version" {
  description = "Eks cluster version"
  type        = string
  default     = "1.30" # assumed; use the version the Mumbai cluster runs
}

variable "eks_node_instance_type" {
  description = "Eks node instance type"
  type        = string
  default     = "m6i.2xlarge" # assumed
}

variable "dr_baseline_nodes" {
  description = "Pre-provisioned Hyderabad nodes (12 of 24 = 50%, cost-summary.md)"
  type        = number
  default     = 12
}

variable "dr_failover_increment_nodes" {
  description = "Extra nodes covered by On-Demand Capacity Reservations"
  type        = number
  default     = 12
}

# ---- DNS ----
variable "route53_zone_id" {
  description = "Route 53 hosted zone ID for paysecure.in"
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

# ---- CI/CD (RB-11 passes -var runner_ami=...) ----
variable "runner_ami" {
  description = "Clean, signed golden AMI for pipeline runners"
  type        = string
}

variable "github_repo" {
  description = "ORG/REPO allowed to assume the deploy role through OIDC"
  type        = string
}

# ---- Tags and operations ----
variable "cost_center" {
  description = "Cost centre tag applied to every resource"
  type        = string
  default     = "platform-dr"
}

variable "dr_tier" {
  description = "DR tier tag: cold, warm, hot or active-active (recommended: hot)"
  type        = string
  default     = "hot"

  validation {
    condition     = contains(["cold", "warm", "hot", "active-active"], var.dr_tier)
    error_message = "dr_tier must be cold, warm, hot or active-active."
  }
}

variable "pagerduty_integration_url" {
  description = "PagerDuty events integration URL for the alert topics (leave empty to skip the subscription)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "alb_arn" {
  description = "ARN of the public payment API ALB (for the WAF association and Shield). Empty = skip"
  type        = string
  default     = ""
}

variable "merchant_ip_cidrs" {
  description = "Merchant server CIDRs for the WAF allow-list (RB-07)"
  type        = list(string)
  default     = []
}

variable "enable_shield_advanced" {
  description = "Protect the ALB with Shield Advanced (needs an active subscription)"
  type        = bool
  default     = false
}

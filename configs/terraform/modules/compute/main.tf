terraform {
  required_providers {
    aws = { source = "hashicorp/aws" }
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 3)
}

# Hyderabad standby cluster `paysecure-dr`: 12 of the 24 Mumbai nodes pre-provisioned (50%),
# the rest covered by On-Demand Capacity Reservations (cost-summary.md Section 4).
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.24"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version
  vpc_id          = var.vpc_id
  subnet_ids      = var.subnet_ids

  # Private endpoint only: operators reach the cluster through the Transit Gateway or VPN.
  cluster_endpoint_public_access  = false
  cluster_endpoint_private_access = true
  enable_irsa                     = true

  cluster_encryption_config = {
    provider_key_arn = var.kms_key_arn
    resources        = ["secrets"]
  }

  cluster_enabled_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  eks_managed_node_groups = {
    app-ng = {
      instance_types = [var.node_instance_type]
      min_size       = var.baseline_nodes
      desired_size   = var.baseline_nodes
      max_size       = var.baseline_nodes + var.failover_increment_nodes
      ami_type       = "AL2023_x86_64_STANDARD"
      labels         = { role = "app", region-role = "dr" }
    }
  }
}

# Capacity for the failover increment is reserved in advance, otherwise capacity may not be
# available in the region during a regional event. Reservations are spread across the 3 AZs.
resource "aws_ec2_capacity_reservation" "failover" {
  count                   = 3
  instance_type           = var.node_instance_type
  instance_platform       = "Linux/UNIX"
  availability_zone       = local.azs[count.index]
  instance_count          = ceil(var.failover_increment_nodes / 3)
  instance_match_criteria = "open"
  tags                    = { Name = "${var.cluster_name}-failover-${count.index}" }
}

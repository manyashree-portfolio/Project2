terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }
}

locals {
  tags = {
    Project     = "paysecure-dr"
    Environment = var.environment
    CostCenter  = var.cost_center
    DR-Tier     = var.dr_tier
    ManagedBy   = "terraform"
    DataClass   = "payment"
  }
}

# Both providers are Indian regions only. Never add a provider outside India.
provider "aws" {
  alias               = "mumbai"
  region              = "ap-south-1"
  allowed_account_ids = var.allowed_account_ids
  default_tags {
    tags = local.tags
  }
}

provider "aws" {
  alias               = "hyderabad"
  region              = "ap-south-2"
  allowed_account_ids = var.allowed_account_ids
  default_tags {
    tags = local.tags
  }
}

terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }
}

# Run from the Organizations management account. Organizations is a global service homed in us-east-1,
# so this one provider is the single, documented exception to "Indian regions only". It stores no payment data.
provider "aws" {
  region = "us-east-1"
}

variable "target_ids" {
  description = "OU or account IDs that hold PaySecure workloads"
  type        = list(string)
}

module "guardrails" {
  source     = "../../modules/guardrails"
  target_ids = var.target_ids
}

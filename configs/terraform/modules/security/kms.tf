terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      configuration_aliases = [aws.primary, aws.secondary]
    }
  }
}

data "aws_caller_identity" "current" {
  provider = aws.primary
}

# The key policy lets IAM manage access, and denies replication anywhere but Hyderabad.
data "aws_iam_policy_document" "key" {
  provider = aws.primary

  statement {
    sid       = "EnableIamPolicies"
    effect    = "Allow"
    actions   = ["kms:*"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }

  statement {
    sid       = "DenyReplicationOutsideIndia"
    effect    = "Deny"
    actions   = ["kms:ReplicateKey"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    condition {
      test     = "StringNotEquals"
      variable = "kms:ReplicaRegion"
      values   = ["ap-south-2"]
    }
  }
}

resource "aws_kms_key" "primary" {
  for_each                = var.keys
  provider                = aws.primary
  description             = "PaySecure ${each.key} multi-Region key"
  multi_region            = true
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy                  = data.aws_iam_policy_document.key.json
  tags                    = { Purpose = each.key }
}

resource "aws_kms_alias" "primary" {
  for_each      = var.keys
  provider      = aws.primary
  name          = each.value
  target_key_id = aws_kms_key.primary[each.key].key_id
}

resource "aws_kms_replica_key" "replica" {
  for_each                = var.keys
  provider                = aws.secondary
  description             = "PaySecure ${each.key} replica key (Hyderabad)"
  primary_key_arn         = aws_kms_key.primary[each.key].arn
  deletion_window_in_days = 30
  policy                  = data.aws_iam_policy_document.key.json
  tags                    = { Purpose = each.key }
}

resource "aws_kms_alias" "replica" {
  for_each      = var.keys
  provider      = aws.secondary
  name          = each.value
  target_key_id = aws_kms_replica_key.replica[each.key].key_id
}

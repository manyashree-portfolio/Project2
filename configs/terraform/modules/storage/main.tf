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

locals {
  acct = data.aws_caller_identity.current.account_id
  buckets = {
    backups = { lock = false }
    audit   = { lock = true } # Object Lock in compliance mode (7-year evidence retention)
  }
}

# ---------------- Buckets: Mumbai (source) and Hyderabad (replica) ----------------
resource "aws_s3_bucket" "primary" {
  for_each            = local.buckets
  provider            = aws.primary
  bucket              = "paysecure-${each.key}-mum-${local.acct}"
  object_lock_enabled = each.value.lock
}

resource "aws_s3_bucket" "secondary" {
  for_each            = local.buckets
  provider            = aws.secondary
  bucket              = "paysecure-${each.key}-hyd-${local.acct}"
  object_lock_enabled = each.value.lock
}

resource "aws_s3_bucket_versioning" "primary" {
  for_each = local.buckets
  provider = aws.primary
  bucket   = aws_s3_bucket.primary[each.key].id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_versioning" "secondary" {
  for_each = local.buckets
  provider = aws.secondary
  bucket   = aws_s3_bucket.secondary[each.key].id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "primary" {
  for_each = local.buckets
  provider = aws.primary
  bucket   = aws_s3_bucket.primary[each.key].id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.primary_kms_key_arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "secondary" {
  for_each = local.buckets
  provider = aws.secondary
  bucket   = aws_s3_bucket.secondary[each.key].id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.secondary_kms_key_arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "primary" {
  for_each                = local.buckets
  provider                = aws.primary
  bucket                  = aws_s3_bucket.primary[each.key].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "secondary" {
  for_each                = local.buckets
  provider                = aws.secondary
  bucket                  = aws_s3_bucket.secondary[each.key].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Object Lock default retention on the audit buckets
resource "aws_s3_bucket_object_lock_configuration" "audit_primary" {
  provider = aws.primary
  bucket   = aws_s3_bucket.primary["audit"].id
  rule {
    default_retention {
      mode  = "COMPLIANCE"
      years = var.audit_retention_years
    }
  }
  depends_on = [aws_s3_bucket_versioning.primary]
}

resource "aws_s3_bucket_object_lock_configuration" "audit_secondary" {
  provider = aws.secondary
  bucket   = aws_s3_bucket.secondary["audit"].id
  rule {
    default_retention {
      mode  = "COMPLIANCE"
      years = var.audit_retention_years
    }
  }
  depends_on = [aws_s3_bucket_versioning.secondary]
}

# TLS only, on both sides
data "aws_iam_policy_document" "tls_primary" {
  provider = aws.primary
  for_each = local.buckets
  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.primary[each.key].arn, "${aws_s3_bucket.primary[each.key].arn}/*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

data "aws_iam_policy_document" "tls_secondary" {
  provider = aws.secondary
  for_each = local.buckets
  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.secondary[each.key].arn, "${aws_s3_bucket.secondary[each.key].arn}/*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "primary" {
  for_each = local.buckets
  provider = aws.primary
  bucket   = aws_s3_bucket.primary[each.key].id
  policy   = data.aws_iam_policy_document.tls_primary[each.key].json
}

resource "aws_s3_bucket_policy" "secondary" {
  for_each = local.buckets
  provider = aws.secondary
  bucket   = aws_s3_bucket.secondary[each.key].id
  policy   = data.aws_iam_policy_document.tls_secondary[each.key].json
}

# ---------------- Replication (CRR + Replication Time Control) ----------------
data "aws_iam_policy_document" "replication_trust" {
  provider = aws.primary
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "replication" {
  provider = aws.primary
  statement {
    actions   = ["s3:GetReplicationConfiguration", "s3:ListBucket"]
    resources = [for b in aws_s3_bucket.primary : b.arn]
  }
  statement {
    actions   = ["s3:GetObjectVersionForReplication", "s3:GetObjectVersionAcl", "s3:GetObjectVersionTagging", "s3:GetObjectRetention", "s3:GetObjectLegalHold"]
    resources = [for b in aws_s3_bucket.primary : "${b.arn}/*"]
  }
  statement {
    actions   = ["s3:ReplicateObject", "s3:ReplicateTags", "s3:ObjectOwnerOverrideToBucketOwner"]
    resources = [for b in aws_s3_bucket.secondary : "${b.arn}/*"]
  }
  statement {
    actions   = ["kms:Decrypt"]
    resources = [var.primary_kms_key_arn]
  }
  statement {
    actions   = ["kms:Encrypt", "kms:GenerateDataKey"]
    resources = [var.secondary_kms_key_arn]
  }
}

resource "aws_iam_role" "replication" {
  provider           = aws.primary
  name               = "paysecure-s3-replication"
  assume_role_policy = data.aws_iam_policy_document.replication_trust.json
}

resource "aws_iam_role_policy" "replication" {
  provider = aws.primary
  name     = "replication"
  role     = aws_iam_role.replication.id
  policy   = data.aws_iam_policy_document.replication.json
}

resource "aws_s3_bucket_replication_configuration" "this" {
  for_each = local.buckets
  provider = aws.primary
  bucket   = aws_s3_bucket.primary[each.key].id
  role     = aws_iam_role.replication.arn

  rule {
    id       = "${each.key}-to-hyderabad"
    status   = "Enabled"
    priority = 1
    filter {}

    # Delete markers are NOT replicated: an accidental or malicious delete in Mumbai
    # cannot remove the Hyderabad copy (replication-strategy.md Section 8).
    delete_marker_replication {
      status = "Disabled"
    }

    source_selection_criteria {
      sse_kms_encrypted_objects {
        status = "Enabled"
      }
    }

    destination {
      bucket        = aws_s3_bucket.secondary[each.key].arn
      storage_class = "STANDARD"
      encryption_configuration {
        replica_kms_key_id = var.secondary_kms_key_arn
      }
      replication_time {
        status = "Enabled"
        time {
          minutes = 15
        }
      }
      metrics {
        status = "Enabled"
        event_threshold {
          minutes = 15
        }
      }
    }
  }

  depends_on = [aws_s3_bucket_versioning.primary, aws_s3_bucket_versioning.secondary]
}

# Any failed replication = P2 (replication-strategy.md Section 10)
resource "aws_cloudwatch_metric_alarm" "failed_replication" {
  for_each          = local.buckets
  provider          = aws.primary
  alarm_name        = "paysecure-s3-${each.key}-replication-failed-p2"
  alarm_description = "P2: S3 replication operations failed for ${each.key}"
  namespace         = "AWS/S3"
  metric_name       = "OperationsFailedReplication"
  dimensions = {
    SourceBucket      = aws_s3_bucket.primary[each.key].bucket
    DestinationBucket = aws_s3_bucket.secondary[each.key].bucket
    RuleId            = "${each.key}-to-hyderabad"
  }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [var.alarm_topic_arn_primary]
}

terraform {
  required_providers {
    aws = { source = "hashicorp/aws" }
  }
}

# India-only Service Control Policy (docs/07-data-sovereignty/compliance-matrix.md, Section 6).
# Global and metadata-only services are exempt. Test in a sandbox OU first.
data "aws_iam_policy_document" "india_only" {
  statement {
    sid    = "DenyOutsideIndia"
    effect = "Deny"
    not_actions = [
      "iam:*", "organizations:*", "sts:*", "route53:*", "route53domains:*",
      "cloudfront:*", "waf:*", "shield:*", "support:*", "health:*",
      "budgets:*", "ce:*", "trustedadvisor:*",
    ]
    resources = ["*"]
    condition {
      test     = "StringNotEquals"
      variable = "aws:RequestedRegion"
      values   = var.allowed_regions
    }
  }
}

resource "aws_organizations_policy" "india_only" {
  name        = "paysecure-india-regions-only"
  description = "Deny all actions outside ap-south-1 and ap-south-2 (RBI storage of payment system data)"
  type        = "SERVICE_CONTROL_POLICY"
  content     = data.aws_iam_policy_document.india_only.json
}

resource "aws_organizations_policy_attachment" "targets" {
  for_each  = toset(var.target_ids)
  policy_id = aws_organizations_policy.india_only.id
  target_id = each.value
}

# Narrow exception: a dedicated operations account may use ap-southeast-1 for the redacted, non-PII operational
# copy (category 4) and nothing else. Payment accounts never get this policy.
data "aws_iam_policy_document" "operations_singapore" {
  statement {
    sid    = "DenyOutsideIndiaAndSingapore"
    effect = "Deny"
    not_actions = [
      "iam:*", "organizations:*", "sts:*", "route53:*", "route53domains:*",
      "cloudfront:*", "waf:*", "shield:*", "support:*", "health:*",
      "budgets:*", "ce:*", "trustedadvisor:*",
    ]
    resources = ["*"]
    condition {
      test     = "StringNotEquals"
      variable = "aws:RequestedRegion"
      values   = concat(var.allowed_regions, ["ap-southeast-1"])
    }
  }
}

resource "aws_organizations_policy" "operations_singapore" {
  count       = length(var.operations_account_ids) > 0 ? 1 : 0
  name        = "paysecure-operations-india-and-singapore"
  description = "Operations account: India regions plus ap-southeast-1 for redacted operational copies"
  type        = "SERVICE_CONTROL_POLICY"
  content     = data.aws_iam_policy_document.operations_singapore.json
}

resource "aws_organizations_policy_attachment" "operations" {
  for_each  = length(var.operations_account_ids) > 0 ? toset(var.operations_account_ids) : toset([])
  policy_id = aws_organizations_policy.operations_singapore[0].id
  target_id = each.value
}

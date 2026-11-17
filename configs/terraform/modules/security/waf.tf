# Regional WAF for the payment API (Mumbai). The Hyderabad web ACL is created the same way in the
# secondary environment so both regions use identical rules (docs section A9: identical WAF rules via IaC).
# The production web ACL already exists: import it before applying.
resource "aws_wafv2_ip_set" "merchants" {
  provider           = aws.primary
  name               = "paysecure-merchant-ips"
  scope              = "REGIONAL"
  ip_address_version = "IPV4"
  addresses          = var.merchant_ip_cidrs
}

resource "aws_wafv2_web_acl" "api" {
  provider    = aws.primary
  name        = "paysecure-waf"
  description = "PaySecure API WAF with a staged emergency rate rule (RB-07)"
  scope       = "REGIONAL"

  default_action {
    allow {}
  }

  rule {
    name     = "allow-known-merchants"
    priority = 0
    action {
      allow {}
    }
    statement {
      ip_set_reference_statement {
        arn = aws_wafv2_ip_set.merchants.arn
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      sampled_requests_enabled   = true
      metric_name                = "allow-known-merchants"
    }
  }

  # Staged in Count mode. RB-07 switches it to Block with waf-rules/waf-emergency-block.json.
  rule {
    name     = "emergency-rate-limit-payments"
    priority = 10
    action {
      count {}
    }
    statement {
      rate_based_statement {
        limit                 = 100
        evaluation_window_sec = 300
        aggregate_key_type    = "IP"
        scope_down_statement {
          byte_match_statement {
            search_string         = "/v1/payments"
            positional_constraint = "STARTS_WITH"
            field_to_match {
              uri_path {}
            }
            text_transformation {
              priority = 0
              type     = "NONE"
            }
          }
        }
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      sampled_requests_enabled   = true
      metric_name                = "emergency-rate-limit-payments"
    }
  }

  rule {
    name     = "aws-managed-common"
    priority = 20
    override_action {
      none {}
    }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      sampled_requests_enabled   = true
      metric_name                = "aws-managed-common"
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    sampled_requests_enabled   = true
    metric_name                = "paysecure-waf"
  }
}

resource "aws_wafv2_web_acl_association" "alb" {
  count        = var.alb_arn == "" ? 0 : 1
  provider     = aws.primary
  resource_arn = var.alb_arn
  web_acl_arn  = aws_wafv2_web_acl.api.arn
}

# Shield Advanced needs a paid subscription (about USD 3,000 a month, cost model). Off by default.
resource "aws_shield_protection" "alb" {
  count        = var.enable_shield_advanced && var.alb_arn != "" ? 1 : 0
  provider     = aws.primary
  name         = "paysecure-api-alb"
  resource_arn = var.alb_arn
}

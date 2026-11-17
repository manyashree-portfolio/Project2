terraform {
  required_providers {
    aws = { source = "hashicorp/aws" }
  }
}

# Mirrors docs/04-dns-failover/route53-config.json and health-check-config.yaml.
# Note: Route 53 health checkers run from AWS locations outside India. They only call the
# /health endpoints, which must never return payment data (docs/07-data-sovereignty, Section 6).

locals {
  checker_regions = ["us-east-1", "eu-west-1", "ap-southeast-1", "ap-southeast-2", "ap-northeast-1"]
}

resource "aws_route53_health_check" "mum_deep" {
  fqdn              = "api-mum.paysecure.in"
  port              = 443
  type              = "HTTPS"
  resource_path     = "/health/deep"
  request_interval  = 10
  failure_threshold = 3
  measure_latency   = true
  enable_sni        = true
  regions           = local.checker_regions
  tags              = { Name = "mum-api-deep-health" }
}

resource "aws_route53_health_check" "mum_synthetic" {
  fqdn              = "api-mum.paysecure.in"
  port              = 443
  type              = "HTTPS"
  resource_path     = "/health/synthetic"
  request_interval  = 10
  failure_threshold = 3
  measure_latency   = true
  enable_sni        = true
  regions           = local.checker_regions
  tags              = { Name = "mum-synthetic-transaction" }
}

resource "aws_route53_health_check" "mum_alarm" {
  type                            = "CLOUDWATCH_METRIC"
  cloudwatch_alarm_name           = var.success_rate_alarm_name
  cloudwatch_alarm_region         = "ap-south-1"
  insufficient_data_health_status = "LastKnownStatus"
  tags                            = { Name = "mum-api-success-rate-alarm" }
}

# HC-MUM-CALCULATED: healthy if at least 2 of 3 children are healthy
resource "aws_route53_health_check" "mum_calculated" {
  type                   = "CALCULATED"
  child_health_threshold = 2
  child_healthchecks = [
    aws_route53_health_check.mum_deep.id,
    aws_route53_health_check.mum_synthetic.id,
    aws_route53_health_check.mum_alarm.id,
  ]
  tags = { Name = "HC-MUM-CALCULATED" }
}

# HC-HYD-LIVE: simple liveness check; deliberately does not require write-readiness
resource "aws_route53_health_check" "hyd_live" {
  fqdn              = "api-hyd.paysecure.in"
  port              = 443
  type              = "HTTPS"
  resource_path     = "/health/live"
  request_interval  = 10
  failure_threshold = 3
  measure_latency   = true
  enable_sni        = true
  regions           = local.checker_regions
  tags              = { Name = "HC-HYD-LIVE" }
}

# CNAME records are used because alias records to an ALB have a fixed 60 s TTL; 30 s here.
resource "aws_route53_record" "primary" {
  zone_id         = var.zone_id
  name            = "api.paysecure.in"
  type            = "CNAME"
  ttl             = var.ttl_seconds
  set_identifier  = "mumbai-primary"
  records         = [var.mum_alb_dns]
  health_check_id = aws_route53_health_check.mum_calculated.id
  failover_routing_policy {
    type = "PRIMARY"
  }
}

resource "aws_route53_record" "secondary" {
  zone_id         = var.zone_id
  name            = "api.paysecure.in"
  type            = "CNAME"
  ttl             = var.ttl_seconds
  set_identifier  = "hyderabad-secondary"
  records         = [var.hyd_alb_dns]
  health_check_id = aws_route53_health_check.hyd_live.id
  failover_routing_policy {
    type = "SECONDARY"
  }
}

resource "aws_route53_record" "api_mum" {
  zone_id = var.zone_id
  name    = "api-mum.paysecure.in"
  type    = "CNAME"
  ttl     = 60
  records = [var.mum_alb_dns]
}

resource "aws_route53_record" "api_hyd" {
  zone_id = var.zone_id
  name    = "api-hyd.paysecure.in"
  type    = "CNAME"
  ttl     = 60
  records = [var.hyd_alb_dns]
}

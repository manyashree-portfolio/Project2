output "health_check_ids" {
  value = {
    mum_calculated = aws_route53_health_check.mum_calculated.id
    hyd_live       = aws_route53_health_check.hyd_live.id
  }
}

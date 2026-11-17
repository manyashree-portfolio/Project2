# Production DR environment. Mumbai (ap-south-1) is primary, Hyderabad (ap-south-2) is the standby.
# All modules use only the two Indian providers declared in providers.tf.

module "kms" {
  source    = "../../modules/security"
  providers = { aws.primary = aws.mumbai, aws.secondary = aws.hyderabad }

  merchant_ip_cidrs      = var.merchant_ip_cidrs
  alb_arn                = var.alb_arn
  enable_shield_advanced = var.enable_shield_advanced
}

module "monitoring" {
  source    = "../../modules/monitoring"
  providers = { aws.primary = aws.mumbai, aws.secondary = aws.hyderabad }

  primary_kms_key_id        = module.kms.primary_key_arns["data"]
  secondary_kms_key_id      = module.kms.replica_key_arns["data"]
  pagerduty_integration_url = var.pagerduty_integration_url
}

module "network_hyderabad" {
  source         = "../../modules/networking"
  providers      = { aws = aws.hyderabad }
  name           = "paysecure-dr"
  vpc_cidr       = var.dr_vpc_cidr
  tgw_asn        = var.transit_gateway_amazon_side_asn
  endpoint_cidrs = [var.dr_vpc_cidr]
}

module "aurora" {
  source    = "../../modules/database"
  providers = { aws.primary = aws.mumbai, aws.secondary = aws.hyderabad }

  primary_vpc_id        = var.primary_vpc_id
  primary_subnet_ids    = var.primary_private_subnet_ids
  primary_allowed_cidrs = [var.primary_vpc_cidr]
  secondary_vpc_id      = module.network_hyderabad.vpc_id
  secondary_subnet_ids  = module.network_hyderabad.private_subnet_ids
  # Mumbai CIDR is allowed in Hyderabad so the DR region can be reached from partner and ops VPNs after a failback.
  secondary_allowed_cidrs = [var.dr_vpc_cidr, var.primary_vpc_cidr]

  primary_kms_key_arn   = module.kms.primary_key_arns["cde"]
  secondary_kms_key_arn = module.kms.replica_key_arns["cde"]

  master_username    = var.db_master_username
  instance_class     = var.aurora_instance_class
  dr_instance_count  = var.aurora_dr_instance_count
  alarm_topic_arn_dr = module.monitoring.alarm_topic_arn_dr
}

module "dynamodb" {
  source    = "../../modules/dynamodb"
  providers = { aws.primary = aws.mumbai, aws.secondary = aws.hyderabad }

  primary_kms_key_arn     = module.kms.primary_key_arns["data"]
  replica_kms_key_arn     = module.kms.replica_key_arns["data"]
  alarm_topic_arn_primary = module.monitoring.alarm_topic_arn_primary
}

module "redis" {
  source    = "../../modules/cache"
  providers = { aws.primary = aws.mumbai, aws.secondary = aws.hyderabad }

  primary_vpc_id          = var.primary_vpc_id
  primary_subnet_ids      = var.primary_private_subnet_ids
  primary_allowed_cidrs   = [var.primary_vpc_cidr]
  secondary_vpc_id        = module.network_hyderabad.vpc_id
  secondary_subnet_ids    = module.network_hyderabad.private_subnet_ids
  secondary_allowed_cidrs = [var.dr_vpc_cidr]
  primary_kms_key_arn     = module.kms.primary_key_arns["data"]
  secondary_kms_key_arn   = module.kms.replica_key_arns["data"]
  node_type               = var.redis_node_type
}

module "messaging" {
  source    = "../../modules/messaging"
  providers = { aws.primary = aws.mumbai, aws.secondary = aws.hyderabad }

  primary_cluster_name   = var.msk_cluster_name
  secondary_cluster_name = "paysecure-dr"
  instance_type          = var.msk_instance_type

  primary_vpc_id          = var.primary_vpc_id
  primary_subnet_ids      = var.primary_private_subnet_ids
  primary_allowed_cidrs   = [var.primary_vpc_cidr]
  secondary_vpc_id        = module.network_hyderabad.vpc_id
  secondary_subnet_ids    = module.network_hyderabad.private_subnet_ids
  secondary_allowed_cidrs = [var.dr_vpc_cidr]

  primary_kms_key_arn   = module.kms.primary_key_arns["data"]
  secondary_kms_key_arn = module.kms.replica_key_arns["data"]
  alarm_topic_arn_dr    = module.monitoring.alarm_topic_arn_dr
}

module "s3" {
  source    = "../../modules/storage"
  providers = { aws.primary = aws.mumbai, aws.secondary = aws.hyderabad }

  primary_kms_key_arn     = module.kms.primary_key_arns["data"]
  secondary_kms_key_arn   = module.kms.replica_key_arns["data"]
  alarm_topic_arn_primary = module.monitoring.alarm_topic_arn_primary
}

module "eks_dr" {
  source    = "../../modules/compute"
  providers = { aws = aws.hyderabad }

  cluster_name             = "paysecure-dr"
  cluster_version          = var.eks_cluster_version
  vpc_id                   = module.network_hyderabad.vpc_id
  subnet_ids               = module.network_hyderabad.private_subnet_ids
  node_instance_type       = var.eks_node_instance_type
  baseline_nodes           = var.dr_baseline_nodes
  failover_increment_nodes = var.dr_failover_increment_nodes
  kms_key_arn              = module.kms.replica_key_arns["data"]
}

module "dns" {
  source    = "../../modules/dns"
  providers = { aws = aws.mumbai }

  zone_id                 = var.route53_zone_id
  mum_alb_dns             = var.mum_alb_dns
  hyd_alb_dns             = var.hyd_alb_dns
  success_rate_alarm_name = module.monitoring.success_rate_alarm_name
}

module "cicd" {
  source    = "../../modules/cicd"
  providers = { aws = aws.mumbai }

  runner_ami  = var.runner_ami
  vpc_id      = var.primary_vpc_id
  subnet_ids  = var.primary_private_subnet_ids
  github_repo = var.github_repo
}

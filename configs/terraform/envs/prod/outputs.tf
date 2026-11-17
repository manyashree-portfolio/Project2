output "aurora_global_cluster_id" {
  value = module.aurora.global_cluster_id
}

output "aurora_secondary_endpoint" {
  value = module.aurora.secondary_endpoint
}

output "msk_replicator_arn" {
  value = module.messaging.replicator_arn
}

output "dr_eks_cluster_name" {
  value = module.eks_dr.cluster_name
}

output "kms_key_arns" {
  value = {
    primary = module.kms.primary_key_arns
    replica = module.kms.replica_key_arns
  }
}

output "api_health_check_ids" {
  value = module.dns.health_check_ids
}

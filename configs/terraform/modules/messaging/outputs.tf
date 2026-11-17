output "replicator_arn" {
  value = aws_msk_replicator.this.arn
}

output "primary_cluster_arn" {
  value = aws_msk_cluster.primary.arn
}

output "secondary_cluster_arn" {
  value = aws_msk_cluster.secondary.arn
}

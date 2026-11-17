terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      configuration_aliases = [aws.primary, aws.secondary]
    }
  }
}

# Redis Global Datastore. The secondary is read-only until promoted; the cache is rebuildable,
# so a Redis loss never causes payment data loss (replication-strategy.md Section 5).

resource "aws_elasticache_subnet_group" "primary" {
  provider   = aws.primary
  name       = "paysecure-redis-mum"
  subnet_ids = var.primary_subnet_ids
}

resource "aws_security_group" "primary" {
  provider    = aws.primary
  name_prefix = "paysecure-redis-mum-"
  vpc_id      = var.primary_vpc_id
  ingress {
    from_port   = 6379
    to_port     = 6379
    protocol    = "tcp"
    cidr_blocks = var.primary_allowed_cidrs
  }
}

# Import the existing Mumbai group first:
#   terraform import module.redis.aws_elasticache_replication_group.mum paysecure-redis-mum
resource "aws_elasticache_replication_group" "mum" {
  provider                   = aws.primary
  replication_group_id       = "paysecure-redis-mum"
  description                = "PaySecure Redis (Mumbai, primary)"
  engine                     = "redis"
  node_type                  = var.node_type
  num_node_groups            = var.shards
  replicas_per_node_group    = 1
  automatic_failover_enabled = true
  multi_az_enabled           = true
  at_rest_encryption_enabled = true
  kms_key_id                 = var.primary_kms_key_arn
  transit_encryption_enabled = true
  subnet_group_name          = aws_elasticache_subnet_group.primary.name
  security_group_ids         = [aws_security_group.primary.id]
}

resource "aws_elasticache_global_replication_group" "this" {
  provider                           = aws.primary
  global_replication_group_id_suffix = "paysecure-redis-global"
  primary_replication_group_id       = aws_elasticache_replication_group.mum.id
}

resource "aws_elasticache_subnet_group" "secondary" {
  provider   = aws.secondary
  name       = "paysecure-redis-hyd"
  subnet_ids = var.secondary_subnet_ids
}

resource "aws_security_group" "secondary" {
  provider    = aws.secondary
  name_prefix = "paysecure-redis-hyd-"
  vpc_id      = var.secondary_vpc_id
  ingress {
    from_port   = 6379
    to_port     = 6379
    protocol    = "tcp"
    cidr_blocks = var.secondary_allowed_cidrs
  }
}

resource "aws_elasticache_replication_group" "hyd" {
  provider                    = aws.secondary
  replication_group_id        = "paysecure-redis-hyd"
  description                 = "PaySecure Redis (Hyderabad, secondary)"
  global_replication_group_id = aws_elasticache_global_replication_group.this.global_replication_group_id
  automatic_failover_enabled  = true
  multi_az_enabled            = true
  kms_key_id                  = var.secondary_kms_key_arn
  subnet_group_name           = aws_elasticache_subnet_group.secondary.name
  security_group_ids          = [aws_security_group.secondary.id]
}

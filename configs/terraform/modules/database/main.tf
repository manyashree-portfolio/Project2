terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      configuration_aliases = [aws.primary, aws.secondary]
    }
  }
}

# The Mumbai cluster already exists in production. Import it first:
#   terraform import module.aurora.aws_rds_cluster.primary paysecure-primary

resource "aws_rds_global_cluster" "this" {
  provider                  = aws.primary
  global_cluster_identifier = "paysecure-global"
  engine                    = "aurora-postgresql"
  engine_version            = "15.4"
  database_name             = "paysecure"
  storage_encrypted         = true
}

# ---------------- Mumbai (primary) ----------------
resource "aws_db_subnet_group" "primary" {
  provider   = aws.primary
  name       = "paysecure-primary"
  subnet_ids = var.primary_subnet_ids
}

resource "aws_security_group" "primary" {
  provider    = aws.primary
  name_prefix = "paysecure-aurora-primary-"
  vpc_id      = var.primary_vpc_id
  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = var.primary_allowed_cidrs
  }
}

resource "aws_rds_cluster" "primary" {
  provider                        = aws.primary
  cluster_identifier              = "paysecure-primary"
  global_cluster_identifier       = aws_rds_global_cluster.this.id
  engine                          = "aurora-postgresql"
  engine_version                  = "15.4"
  database_name                   = "paysecure"
  master_username                 = var.master_username
  manage_master_user_password     = true
  master_user_secret_kms_key_id   = var.primary_kms_key_arn
  storage_encrypted               = true
  kms_key_id                      = var.primary_kms_key_arn
  db_subnet_group_name            = aws_db_subnet_group.primary.name
  vpc_security_group_ids          = [aws_security_group.primary.id]
  backup_retention_period         = 35
  deletion_protection             = true
  copy_tags_to_snapshot           = true
  enabled_cloudwatch_logs_exports = ["postgresql"]
  skip_final_snapshot             = false
  final_snapshot_identifier       = "paysecure-primary-final"
}

# 1 writer + 2 readers, as in current-architecture.md
resource "aws_rds_cluster_instance" "primary" {
  count                = 3
  provider             = aws.primary
  identifier           = "paysecure-primary-${count.index}"
  cluster_identifier   = aws_rds_cluster.primary.id
  engine               = aws_rds_cluster.primary.engine
  engine_version       = aws_rds_cluster.primary.engine_version
  instance_class       = var.instance_class
  promotion_tier       = count.index
  db_subnet_group_name = aws_db_subnet_group.primary.name
}

# ---------------- Hyderabad (secondary) ----------------
resource "aws_db_subnet_group" "secondary" {
  provider   = aws.secondary
  name       = "paysecure-secondary"
  subnet_ids = var.secondary_subnet_ids
}

resource "aws_security_group" "secondary" {
  provider    = aws.secondary
  name_prefix = "paysecure-aurora-secondary-"
  vpc_id      = var.secondary_vpc_id
  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = var.secondary_allowed_cidrs
  }
}

resource "aws_rds_cluster" "secondary" {
  provider                  = aws.secondary
  cluster_identifier        = "paysecure-secondary"
  global_cluster_identifier = aws_rds_global_cluster.this.id
  engine                    = "aurora-postgresql"
  engine_version            = "15.4"
  source_region             = "ap-south-1"
  storage_encrypted         = true
  kms_key_id                = var.secondary_kms_key_arn
  db_subnet_group_name      = aws_db_subnet_group.secondary.name
  vpc_security_group_ids    = [aws_security_group.secondary.id]
  deletion_protection       = true
  skip_final_snapshot       = false
  final_snapshot_identifier = "paysecure-secondary-final"

  depends_on = [aws_rds_cluster_instance.primary]

  lifecycle {
    ignore_changes = [replication_source_identifier]
  }
}

resource "aws_rds_cluster_instance" "secondary" {
  count                = var.dr_instance_count
  provider             = aws.secondary
  identifier           = "paysecure-secondary-${count.index}"
  cluster_identifier   = aws_rds_cluster.secondary.id
  engine               = aws_rds_cluster.secondary.engine
  engine_version       = aws_rds_cluster.secondary.engine_version
  instance_class       = var.instance_class
  promotion_tier       = count.index
  db_subnet_group_name = aws_db_subnet_group.secondary.name
}

# ---------------- Alarm: replication-strategy.md Section 10 ----------------
# Aurora Global DB lag above 500 ms for 2 consecutive checks = P1. The metric is published in the secondary region.
resource "aws_cloudwatch_metric_alarm" "replication_lag" {
  provider            = aws.secondary
  alarm_name          = "paysecure-aurora-global-replication-lag-p1"
  alarm_description   = "P1: Aurora global replication lag above 500 ms (RPO risk)"
  namespace           = "AWS/RDS"
  metric_name         = "AuroraGlobalDBReplicationLag"
  dimensions          = { DBClusterIdentifier = aws_rds_cluster.secondary.cluster_identifier }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 2
  datapoints_to_alarm = 2
  threshold           = 500
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "breaching"
  alarm_actions       = [var.alarm_topic_arn_dr]
  ok_actions          = [var.alarm_topic_arn_dr]
}

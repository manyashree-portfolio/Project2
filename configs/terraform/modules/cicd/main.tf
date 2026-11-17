terraform {
  required_providers {
    aws = { source = "hashicorp/aws" }
  }
}

# RB-11 step 20: rebuild the pipeline from clean IaC with a new identity:
#   terraform -chdir=configs/terraform/envs/prod apply -target=module.cicd -var 'runner_ami=ami-CLEAN'

# ---------------- Runner fleet ----------------
resource "aws_security_group" "runner" {
  name_prefix = "paysecure-runner-"
  vpc_id      = var.vpc_id
  description = "Pipeline runners: no inbound, outbound HTTPS only (egress default-deny, RB-11 improvement)"
  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.egress_cidrs
  }
}

data "aws_iam_policy_document" "runner_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "runner" {
  name_prefix        = "paysecure-runner-"
  assume_role_policy = data.aws_iam_policy_document.runner_trust.json
}

resource "aws_iam_role_policy_attachment" "runner_ssm" {
  role       = aws_iam_role.runner.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "runner" {
  name_prefix = "paysecure-runner-"
  role        = aws_iam_role.runner.name
}

resource "aws_launch_template" "runner" {
  name_prefix   = "paysecure-runner-"
  image_id      = var.runner_ami
  instance_type = var.instance_type

  iam_instance_profile {
    arn = aws_iam_instance_profile.runner.arn
  }

  metadata_options {
    http_tokens                 = "required" # IMDSv2 only
    http_put_response_hop_limit = 1
  }

  network_interfaces {
    associate_public_ip_address = false
    security_groups             = [aws_security_group.runner.id]
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      encrypted   = true
      volume_size = 100
    }
  }
}

resource "aws_autoscaling_group" "runner" {
  name_prefix         = "paysecure-runner-"
  min_size            = 0
  desired_capacity    = var.runner_count
  max_size            = var.runner_count * 2
  vpc_zone_identifier = var.subnet_ids

  launch_template {
    id      = aws_launch_template.runner.id
    version = "$Latest"
  }

  # Runners are immutable and short-lived: replaced regularly from the golden AMI.
  instance_refresh {
    strategy = "Rolling"
  }
}

# ---------------- OIDC deploy identity (no long-lived keys) ----------------
resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = var.github_oidc_thumbprints
}

data "aws_iam_policy_document" "deploy_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repo}:ref:refs/heads/main"]
    }
  }
}

resource "aws_iam_role" "deploy" {
  name                 = "paysecure-pipeline-deploy"
  assume_role_policy   = data.aws_iam_policy_document.deploy_trust.json
  max_session_duration = 3600 # short-lived credentials only
}

# Deliberately empty: attach the least-privilege deploy policy per environment.

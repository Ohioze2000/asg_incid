terraform {
  required_version = ">= 1.5.0" # Ensures compatibility with modern public/private TF cloud agents

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.62.0" # FIXED: Allows patch/minor updates while locking major versions
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

# ==========================================
# CORE NETWORKING & SECURITY
# ==========================================

resource "aws_vpc" "my-vpc" {
  cidr_block           = var.vpc_cidr_block
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.env_prefix}-vpc"
  }
}

module "my-network" {
  source         = "./modules/network"
  vpc_id         = aws_vpc.my-vpc.id
  env_prefix     = var.env_prefix
  az_count       = var.az_count
  vpc_cidr_block = var.vpc_cidr_block
}

module "ec2_ssm_role-iam" {
  source                    = "./modules/iam"
  env_prefix                = var.env_prefix
  iam_instance_profile_name = "${var.env_prefix}-ec2-ssm-instance-profile"
}

# ==========================================
# PUBLIC INGRESS & DOMAIN MANAGEMENT
# ==========================================

module "my-ssl" {
  source      = "./modules/ssl"
  domain_name = var.domain_name
}

# FIXED CYCLE STEP 1: Core Domain Zone resolution must run independent of ALB instantiation
module "my-dns" {
  source       = "./modules/dns"
  domain_name  = var.domain_name
  env_prefix   = var.env_prefix
  alb_dns_name = module.my-alb.alb_dns_name
  alb_zone_id  = module.my-alb.zone_id
}

locals {
  root_cert_validation_records = {
    for dvo in module.my-ssl.domain_validation_options : dvo.domain_name => {
      name    = dvo.resource_record_name
      type    = dvo.resource_record_type
      record  = dvo.resource_record_value
      zone_id = module.my-dns.zone_id 
    }
  }
}

resource "aws_route53_record" "cert_validation_root" {
  for_each = local.root_cert_validation_records

  zone_id = each.value.zone_id
  name    = each.value.name
  type    = each.value.type
  ttl     = 60
  records = [each.value.record]
}

# FIXED CYCLE STEP 2: Certification state validation blocks execution down to ALB module
resource "aws_acm_certificate_validation" "cert_validation" {
  certificate_arn         = module.my-ssl.certificate_arn
  validation_record_fqdns = [for rec in aws_route53_record.cert_validation_root : rec.fqdn]
}

# FIXED CYCLE STEP 3: ALB takes validated certificate ARN. Implicit dependency handles sequencing.
module "my-alb" {
  source          = "./modules/alb"
  env_prefix      = var.env_prefix
  vpc_id          = aws_vpc.my-vpc.id
  subnet_ids      = module.my-network.public_subnet_ids
  certificate_arn = aws_acm_certificate_validation.cert_validation.certificate_arn 
}

# ==========================================
# COMPUTE & RUNTIME ORCHESTRATION
# ==========================================

module "my-server" {
  source                    = "./modules/webserver"
  vpc_id                    = aws_vpc.my-vpc.id
  az_count                  = var.az_count
  instance_type             = var.instance_type
  public_key_content        = var.public_key_content
  env_prefix                = var.env_prefix
  private_subnet_ids        = module.my-network.private_subnet_ids
  image_name                = var.image_name
  alb_security_group_id     = module.my-alb.alb_security_group_id
  iam_instance_profile_name = module.ec2_ssm_role-iam.iam_instance_profile_name
  target_group_arn          = module.my-alb.target_group_arn
  desired_capacity          = var.desired_capacity
  max_size                  = var.max_size
  min_size                  = var.min_size
}

# ==========================================
# OBSERVABILITY & SIGNALING
# ==========================================

module "my-monitoring" {
  source            = "./modules/monitoring"
  env_prefix        = var.env_prefix
  asg_name          = module.my-server.asg_name
  target_group_arn  = module.my-alb.target_group_arn
  slack_webhook_url = var.slack_webhook_url
}
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.62"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.common_tags
  }
}

resource "aws_vpc" "ma-vpc" {
  cidr_block           = var.vpc_cidr_block
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(
    var.tags,
    {
      Name = "${var.env_prefix}-vpc"
    }
  )
}

# ==============================================================================
# LOCAL VARIABLES
# ==============================================================================

locals {
  common_tags = merge(
    var.tags,
    {
      Environment = var.env_prefix
      ManagedBy   = "Terraform"
    }
  )

  # Map ACM Domain Validation Options for Route 53 validation records
  cert_validation_map = {
    for dvo in module.ssl.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }
}

# ==============================================================================
# 1. CORE VPC & NETWORKING MODULES
# ==============================================================================

module "network" {
  source         = "./modules/network"
  vpc_id         = aws_vpc.ma-vpc.id
  env_prefix     = var.env_prefix
  az_count       = var.az_count
  vpc_cidr_block = var.vpc_cidr_block
  tags           = local.common_tags
}

# ==============================================================================
# 2. SSL & DNS INFRASTRUCTURE
# ==============================================================================

module "ssl" {
  source      = "./modules/ssl"
  domain_name = var.domain_name
  tags        = local.common_tags
}

module "dns" {
  source       = "./modules/dns"
  domain_name  = var.domain_name
  env_prefix   = var.env_prefix
  alb_dns_name = module.alb.alb_dns_name
  alb_zone_id  = module.alb.alb_zone_id
  tags         = local.common_tags
}

resource "aws_route53_record" "cert_validation" {
  for_each = local.cert_validation_map

  allow_overwrite = true
  zone_id         = module.dns.zone_id
  name            = each.value.name
  type            = each.value.type
  records         = [each.value.record]
  ttl             = 60
}

resource "aws_acm_certificate_validation" "cert_validation" {
  certificate_arn         = module.ssl.certificate_arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}

# ==============================================================================
# 3. APPLICATION LOAD BALANCER
# ==============================================================================

module "alb" {
  source          = "./modules/alb"
  env_prefix      = var.env_prefix
  vpc_id          = module.network.vpc_id
  subnet_ids      = module.network.public_subnet_ids
  
  # Known at plan-time to avoid count evaluation errors
  certificate_arn = module.ssl.certificate_arn 
  
  tags            = local.common_tags

  # Ensure validation completes before listeners are attached
  depends_on = [
    aws_acm_certificate_validation.cert_validation
  ]
}

# ==============================================================================
# 4. IAM SECURITY ROLES
# ==============================================================================

module "iam" {
  source     = "./modules/iam"
  env_prefix = var.env_prefix
  tags       = local.common_tags
}

# ==============================================================================
# 5. COMPUTE & AUTO SCALING TIER
# ==============================================================================

module "webserver" {
  source                    = "./modules/webserver"
  env_prefix                = var.env_prefix
  vpc_id                    = aws_vpc.ma-vpc.id
  private_subnet_ids        = module.network.private_subnet_ids
  alb_security_group_id     = module.alb.alb_security_group_id
  target_group_arn          = module.alb.target_group_arn
  iam_instance_profile_name = module.iam.iam_instance_profile_name
  instance_type             = var.instance_type
  image_name                = var.image_name
  public_key_content        = var.public_key_content
  desired_capacity          = var.desired_capacity
  min_size                  = var.min_size
  max_size                  = var.max_size
  tags                      = local.common_tags
}

# ==============================================================================
# 6. MONITORING & AUTOMATED REMEDIATION
# ==============================================================================

module "monitoring" {
  source            = "./modules/monitoring"
  env_prefix        = var.env_prefix
  asg_name          = module.webserver.asg_name
  target_group_arn  = module.alb.target_group_arn
  slack_webhook_url = var.slack_webhook_url
  tags              = local.common_tags
}

# ==============================================================================
# 7. APPLICATION LOGGING & OBSERVABILITY
# ==============================================================================

module "logging" {
  source                     = "./modules/logging"
  env_prefix                 = var.env_prefix
  default_log_retention_days = var.default_log_retention_days
  log_groups                 = var.log_groups
  metric_filters             = var.metric_filters
  app_alarms                 = var.app_alarms
  alarm_sns_topic_arns       = [module.monitoring.cloudwatch_alarms_topic_arn]
  tags                       = local.common_tags
}

module "app_logging" {
  source     = "./modules/logging"
  env_prefix = var.env_prefix

  # Send notifications to the SNS topic created in the monitoring module
  alarm_sns_topic_arns = [module.monitoring.cloudwatch_alarms_topic_arn]

  # 1. Log Groups
  log_groups = {
    web_app = { retention_in_days = 30 }
    api_gateway = { retention_in_days = 14 }
  }

  # 2. Metric Filters (Parsing log data into quantifiable metrics)
  metric_filters = {
    http_5xx_errors = {
      log_group_key    = "web_app"
      pattern          = "[host, logName, user, timestamp, request, statusCode = 5*, size]"
      metric_name      = "HTTP5xxCount"
      metric_namespace = "AppMetrics"
    }
    database_timeouts = {
      log_group_key    = "web_app"
      pattern          = "?ERROR ?Timeout ?\"Connection refused\""
      metric_name      = "DBConnectionTimeoutCount"
      metric_namespace = "AppMetrics"
    }
  }

  # 3. Application Alarms
  app_alarms = {
    high_5xx_rate = {
      metric_name      = "HTTP5xxCount"
      metric_namespace = "AppMetrics"
      threshold        = 10
      period           = 300
      description      = "Triggers when HTTP 5xx responses exceed 10 in 5 minutes"
    }
    db_connectivity_failure = {
      metric_name      = "DBConnectionTimeoutCount"
      metric_namespace = "AppMetrics"
      threshold        = 1
      period           = 60
      description      = "Triggers immediately if any database connection timeouts are logged"
    }
  }

  tags = local.common_tags
}
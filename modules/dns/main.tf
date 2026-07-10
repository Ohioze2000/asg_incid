# Create Hosted Zone
data "aws_route53_zone" "primary" {
  name = "${var.domain_name}."
  private_zone = false
}

# Route 53 Hosted Zone
resource "aws_route53_record" "root" {
  zone_id = data.aws_route53_zone.primary.zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = var.alb_dns_name        # or aws_instance.web.public_dns
    zone_id                = var.alb_zone_id        # ALB zone ID
    evaluate_target_health = true
  }
}

# Alias record for the www subdomain
resource "aws_route53_record" "www" {
  zone_id = data.aws_route53_zone.primary.zone_id
  name    = "www.${var.domain_name}" # The www subdomain
  type    = "A"
  alias {
    name                   = var.alb_dns_name
    zone_id                = var.alb_zone_id
    evaluate_target_health = true
  }
  
}


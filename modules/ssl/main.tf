# Create ACM Certificate
resource "aws_acm_certificate" "cert" {
  domain_name       = var.domain_name
  
  validation_method = "DNS"

  subject_alternative_names = ["www.${var.domain_name}"]

  tags = {
    Name = "SSL certificate for ${var.domain_name}"
  }
}
output "website_url" {
  description = "The fully qualified domain name (FQDN) of the www subdomain record."
  value       = aws_route53_record.www.fqdn
}

output "root_url" {
  description = "The fully qualified domain name (FQDN) of the root apex record."
  value       = aws_route53_record.root.fqdn
}

output "name_servers" {
  description = "The name servers assigned to this hosted zone. Map these in your domain registrar's control panel."
  value       = data.aws_route53_zone.primary.name_servers
}

output "zone_id" {
  description = "The Route 53 Hosted Zone ID used for record routing."
  value       = data.aws_route53_zone.primary.zone_id
}

output "zone_name" {
  description = "The clean domain name string verified by the hosted zone lookup."
  value       = data.aws_route53_zone.primary.name
}
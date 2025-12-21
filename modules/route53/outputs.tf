// Get name servers
output "nameservers" {
  description = "The authoritative nameservers for the domain."
  value       = data.aws_route53_zone.existing.name_servers
}

output "cert_arn" {
  description = "certificate arn for validation"
  value = aws_acm_certificate_validation.cert_validation.certificate_arn
}

// Get name servers
output "route53_nameservers" {
  description = "The authoritative nameservers for the domain."
  value       = module.route53.nameservers
}

output "s3_filez" {
  description = "S3 Bucket Filez"
  value = module.s3.filez
}

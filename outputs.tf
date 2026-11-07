// Get name servers
output "route53_nameservers" {
  description = "The authoritative nameservers for the domain."
  value       = module.route53.nameservers
}

output "cloudfront_distribution_id" {
  description = "The ID of the CloudFront distribution (used by deploy.sh)"
  value       = module.cloudfront.distribution_id
}

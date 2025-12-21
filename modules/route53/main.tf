# Find the hosted zone that already exists
data "aws_route53_zone" "existing" {
  # You can look it up by name (must end with a trailing dot)
  name = "${var.domain_name}."
  # Optional: restrict to public or private zones
  # private_zone = false
}


# resource "aws_route53_zone" "primary" {
#   name = var.domain_name
# }


# Create the Alias Record for the root domain (e.g., yourdomain.com)
resource "aws_route53_record" "root_alias" {
  zone_id = data.aws_route53_zone.existing.zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = var.cloudfront_domain_name
    zone_id                = var.cloudfront_zone_id
    evaluate_target_health = false
  }
}


# Create a 'www' CNAME record for sub-domain (e.g., www.yourdomain.com)
resource "aws_route53_record" "www_alias" {
  zone_id = data.aws_route53_zone.existing.zone_id
  name    = "www.${var.domain_name}"
  type    = "A"

  alias {
    name                   = var.cloudfront_domain_name
    zone_id                = var.cloudfront_zone_id
    evaluate_target_health = false
  }
}


# Request a public certificate for your domain(s)
resource "aws_acm_certificate" "cert" {
  provider          = aws.acm
  domain_name       = var.domain_name
  validation_method = "DNS"
  subject_alternative_names = [
    "*.${var.domain_name}"
  ]
}


# Use existing Route 53 DNS records for ACM validation
resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.cert.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      type   = dvo.resource_record_type
      record = dvo.resource_record_value
    }
  }

  zone_id = data.aws_route53_zone.existing.zone_id
  name    = each.value.name
  type    = each.value.type
  ttl     = 60
  records = [each.value.record]

  allow_overwrite = true   # optional, prevents race conditions
}


# Wait for the certificate to be validated
resource "aws_acm_certificate_validation" "cert_validation" {
  provider                = aws.acm
  certificate_arn         = aws_acm_certificate.cert.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}

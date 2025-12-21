variable "domain_name" {
  description = "Route53 domain name"
  type = string
}

variable "cloudfront_domain_name" {
  description = "Cloudfront domain name"
  type = string
}

variable "cloudfront_zone_id" {
  description = "Cloudfront zone id"
  type = string
}

# variable "s3_bucket_domain_name" {
#   description = "S3 bucket domain name (without http/https)"
#   type        = string
# }

variable "s3_bucket_regional_domain_name" {
  description = "S3 bucket regional domain name"
  type = string
}

variable "s3_bucket_default_root_object" {
  description = "this points to index.html, and is used both for default root, and cloudfront error redirection to index"
  type        = string
}

variable "s3_origin_id" {
  description = "S3 origin id"
  type = string
}

variable "price_class" {
  description = "price class"
  type        = string
}

variable "oac_name" {
  description = "Cloudfront Object Access Control Name"
  type = string
}

variable "domain_name" {
  description = "the actual domain name for the site (e.g. yourdomain.com)"
  type = string
}

variable "r53_cert_arn" {
  description = "Route53 Cert ARN"
  type = string
}

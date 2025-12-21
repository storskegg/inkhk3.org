variable "bucket_name" {
  description = "Name of the bucket"
  type = string
}

variable "cloudfront_arn" {
  description = "CloudFront Distribution ARN"
  type        = string
}

variable "default_root_object" {
  description = "index.html"
  type = string
}

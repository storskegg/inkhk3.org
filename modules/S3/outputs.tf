output "bucket_names" {
  description = "The name of the created S3 bucket"
  value       = aws_s3_bucket.s3_bucket.bucket
}

output "bucket_website_endpoint" {
  description = "The website endpoint URL of the S3 bucket"
  value       = aws_s3_bucket_website_configuration.s3_bucket.website_endpoint
}

output "bucket_regional_domain_name" {
  description = "The S3 bucket regional domain name"
  value       = aws_s3_bucket.s3_bucket.bucket_regional_domain_name
}

output "bucket_domain_name" {
  description = "The S3 bucket domain name"
  value = aws_s3_bucket.s3_bucket.bucket_domain_name
}

output "filez" {
  description = "S3 Bucket Filez"
  value = fileset(local.path_to_files, "**/*")
}

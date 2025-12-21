output "domain_name" {
  value = aws_cloudfront_distribution.s3_distribution.domain_name
}

output "distribution_id" {
  description = "The ID of the CloudFront distribution"
  value       = aws_cloudfront_distribution.s3_distribution.id
}

output "distribution_arn" {
  description = "The ARN of the CloudFront distribution"
  value       = aws_cloudfront_distribution.s3_distribution.arn
}

output "zone_id" {
  value = aws_cloudfront_distribution.s3_distribution.hosted_zone_id
}

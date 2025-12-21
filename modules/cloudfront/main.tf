resource "aws_cloudfront_distribution" "s3_distribution" {
  origin {
    domain_name              = var.s3_bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.oac.id
    origin_id                = var.s3_origin_id
  }

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "Distribution for inkhk3.org static s3 site"
  default_root_object = var.s3_bucket_default_root_object

  # this will go inside the aws_cloudfront_distribution.s3_distribution block
  custom_error_response {
    error_code         = 403
    response_code      = 404 # Show a 404, even if S3 returns 403 (due to OAC)
    response_page_path = "/${var.s3_bucket_default_root_object}" # Assuming single page app or index page handles errors
    error_caching_min_ttl = 300
  }

  custom_error_response {
    error_code         = 404
    response_code      = 404
    response_page_path = "/${var.s3_bucket_default_root_object}"
    error_caching_min_ttl = 300
  }

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = var.s3_origin_id

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400

    response_headers_policy_id = aws_cloudfront_response_headers_policy.security_headers.id
  }

  price_class = var.price_class

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  # Removed: cloudfront_default_certificate = true
  viewer_certificate {
    acm_certificate_arn      = var.r53_cert_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  aliases = [
    var.domain_name,
    "www.${var.domain_name}"
  ]
}


resource "aws_cloudfront_origin_access_control" "oac" {
  name                              = var.oac_name
  description                       = "Policy for inkhk3.org S3+Cloudfront"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}


# Create a CloudFront Response Headers Policy
resource "aws_cloudfront_response_headers_policy" "security_headers" {
  name    = "Security-Headers-Policy"
  comment = "Adds standard security headers to all responses."

  security_headers_config {
    content_security_policy {
      content_security_policy = "default-src 'self'; style-src 'self' 'unsafe-inline';" # Adjust as needed
      override                = true
    }

    strict_transport_security {
      access_control_max_age_sec = 31536000
      include_subdomains         = true
      override                   = true
      preload                    = true
    }

    xss_protection {
      mode_block   = true
      protection = true
      override   = true
    }

    frame_options {
      frame_option = "DENY"
      override     = true
    }

    content_type_options {
      override = true
    }
  }
}

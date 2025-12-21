locals {
  # S3
  s3_bucket_name = "static-site-inkhk3-org"
  s3_default_root_object = "index.html"
  s3_origin_id = "S3-Static-Website"

  # Route53
  r53_domain_name = "inkhk3.org" # actual site domain

  # Cloudfront
  cf_price_class = "PriceClass_100"
  cf_oac_name = "inkhk3-org-oac"
}

module "s3" {
  source      = "./modules/S3"
  bucket_name = local.s3_bucket_name
  cloudfront_arn = module.cloudfront.distribution_arn
  default_root_object = local.s3_default_root_object
}


module "cloudfront" {
  source                = "./modules/cloudfront"
  # s3_bucket_domain_name = module.s3.bucket_domain_name
  s3_bucket_regional_domain_name = module.s3.bucket_regional_domain_name
  s3_bucket_default_root_object = local.s3_default_root_object
  s3_origin_id = local.s3_origin_id
  price_class = local.cf_price_class
  oac_name = local.cf_oac_name
  domain_name = local.r53_domain_name
  r53_cert_arn = module.route53.cert_arn
}


module "route53" {
  source                 = "./modules/route53"
  domain_name            = local.r53_domain_name
  cloudfront_domain_name = module.cloudfront.domain_name
  cloudfront_zone_id     = module.cloudfront.zone_id

  providers = {
    aws     = aws
    aws.acm = aws.acm
  }
}

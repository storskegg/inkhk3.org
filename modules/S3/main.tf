resource "aws_s3_bucket" "s3_bucket" {
  bucket = var.bucket_name
}


resource "aws_s3_bucket_website_configuration" "s3_bucket" {
  bucket = aws_s3_bucket.s3_bucket.id

  index_document {
    suffix = var.default_root_object
  }
}


resource "aws_s3_bucket_public_access_block" "block" {
  bucket = aws_s3_bucket.s3_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}


# Site content is now uploaded by deploy.sh, not Terraform. This hands the existing
# objects over: they are dropped from state but NOT deleted from the bucket.
removed {
  from = aws_s3_object.object

  lifecycle {
    destroy = false
  }
}


resource "aws_s3_bucket_policy" "allow_cf" {
  bucket = aws_s3_bucket.s3_bucket.id
  depends_on = [ aws_s3_bucket_public_access_block.block ]
  policy = jsonencode({
    "Version": "2012-10-17",
    "Statement": [
      {
        "Sid": "AllowCloudFrontServicePrincipal",
        "Effect": "Allow",
        "Principal": {
          "Service": "cloudfront.amazonaws.com"
        },
        "Action": [
          "s3:GetObject"
        ],
        "Resource": "${aws_s3_bucket.s3_bucket.arn}/*",
        Condition: {
          "StringEquals": {
            "AWS:SourceArn": var.cloudfront_arn
          }
        }
      }
    ]
  })
}

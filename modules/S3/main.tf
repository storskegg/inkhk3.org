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


resource "aws_s3_object" "object" {
  for_each = fileset(local.path_to_files, "**/*")
  bucket = aws_s3_bucket.s3_bucket.id
  key    = each.value
  source = "${local.path_to_files}/${each.value}"
  etag = filemd5("${local.path_to_files}/${each.value}")
  content_type = lookup({
    "html" = "text/html",
    "css"  = "text/css",
    "js"   = "application/javascript",
    "json" = "application/json",
    "png"  = "image/png",
    "jpg"  = "image/jpeg",
    "jpeg" = "image/jpeg",
    "gif"  = "image/gif",
    "svg"  = "image/svg+xml",
    "ico"  = "image/x-icon",
    "txt"  = "text/plain",
    "ttf"  = "font/ttf",
    "TTF"  = "font/ttf"
  }, split(".", each.value)[length(split(".", each.value)) - 1], "application/octet-stream")
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

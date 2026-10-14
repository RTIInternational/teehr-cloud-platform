# Static maintenance page and status.json, served by CloudFront from S3 so it
# stays up while the cluster is down. See docs/maintenance-page.md.

resource "aws_s3_bucket" "maintenance" {
  bucket = "${var.environment}-${var.project_name}-maintenance-page"

  tags = {
    Name        = "${var.environment}-${var.project_name}-maintenance-page"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_s3_bucket_public_access_block" "maintenance" {
  bucket = aws_s3_bucket.maintenance.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "maintenance" {
  bucket = aws_s3_bucket.maintenance.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "cloudfront.amazonaws.com" }
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.maintenance.arn}/*"
        Condition = {
          StringEquals = { "AWS:SourceArn" = aws_cloudfront_distribution.maintenance.arn }
        }
      }
    ]
  })
}

resource "aws_s3_object" "maintenance_index" {
  bucket        = aws_s3_bucket.maintenance.id
  key           = "index.html"
  source        = "${path.module}/maintenance/index.html"
  etag          = filemd5("${path.module}/maintenance/index.html")
  content_type  = "text/html; charset=utf-8"
  cache_control = "max-age=300"
}

resource "aws_s3_object" "maintenance_status" {
  bucket = aws_s3_bucket.maintenance.id
  key    = "status.json"
  content = jsonencode({
    maintenance = var.maintenance_mode
    message     = var.maintenance_message
  })
  content_type  = "application/json"
  cache_control = "no-cache"
}

resource "aws_acm_certificate" "maintenance" {
  provider = aws.us_east_1

  domain_name       = "*.${var.dns_zone_name}"
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "maintenance_cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.maintenance.domain_validation_options : dvo.domain_name => dvo
  }

  zone_id = aws_route53_zone.teehr.zone_id
  name    = each.value.resource_record_name
  type    = each.value.resource_record_type
  records = [each.value.resource_record_value]
  ttl     = 300
}

# Blocks until ACM sees the validation record, which only resolves publicly
# once the Azure NS delegation is in place.
resource "aws_acm_certificate_validation" "maintenance" {
  provider = aws.us_east_1

  certificate_arn         = aws_acm_certificate.maintenance.arn
  validation_record_fqdns = [for r in aws_route53_record.maintenance_cert_validation : r.fqdn]
}

resource "aws_cloudfront_origin_access_control" "maintenance" {
  name                              = "${var.environment}-${var.project_name}-maintenance-page"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_function" "maintenance_request" {
  name    = "${var.environment}-${var.project_name}-maintenance-request"
  runtime = "cloudfront-js-2.0"
  publish = true
  code    = file("${path.module}/maintenance/viewer-request.js")
}

resource "aws_cloudfront_function" "maintenance_response" {
  name    = "${var.environment}-${var.project_name}-maintenance-response"
  runtime = "cloudfront-js-2.0"
  publish = true
  code    = file("${path.module}/maintenance/viewer-response.js")
}

data "aws_cloudfront_cache_policy" "caching_optimized" {
  name = "Managed-CachingOptimized"
}

data "aws_cloudfront_cache_policy" "caching_disabled" {
  name = "Managed-CachingDisabled"
}

# Managed-SimpleCORS omits Access-Control-Allow-Origin when the request carries
# any non-safelisted header, e.g. the Pragma/Cache-Control that browsers add to
# fetch(..., { cache: "no-store" }), so allow all request headers.
resource "aws_cloudfront_response_headers_policy" "status_cors" {
  name = "${var.environment}-${var.project_name}-status-cors"

  cors_config {
    access_control_allow_credentials = false
    origin_override                  = true

    access_control_allow_headers {
      items = ["*"]
    }
    access_control_allow_methods {
      items = ["GET", "HEAD", "OPTIONS"]
    }
    access_control_allow_origins {
      items = ["*"]
    }
  }
}

resource "aws_cloudfront_distribution" "maintenance" {
  enabled         = true
  is_ipv6_enabled = true
  http_version    = "http2and3"
  price_class     = "PriceClass_100"
  comment         = "${var.dns_zone_name} maintenance page"
  aliases         = ["*.${var.dns_zone_name}"]

  origin {
    origin_id                = "maintenance-s3"
    domain_name              = aws_s3_bucket.maintenance.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.maintenance.id
  }

  # Fetched by the app banners from other origins, so it needs CORS and must
  # never be stale.
  ordered_cache_behavior {
    path_pattern               = "/status.json"
    target_origin_id           = "maintenance-s3"
    viewer_protocol_policy     = "redirect-to-https"
    allowed_methods            = ["GET", "HEAD", "OPTIONS"]
    cached_methods             = ["GET", "HEAD"]
    cache_policy_id            = data.aws_cloudfront_cache_policy.caching_disabled.id
    response_headers_policy_id = aws_cloudfront_response_headers_policy.status_cors.id
  }

  default_cache_behavior {
    target_origin_id       = "maintenance-s3"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods         = ["GET", "HEAD"]
    cache_policy_id        = data.aws_cloudfront_cache_policy.caching_optimized.id

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.maintenance_request.arn
    }

    function_association {
      event_type   = "viewer-response"
      function_arn = aws_cloudfront_function.maintenance_response.arn
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.maintenance.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }
}

# HEFS-FEWS data bucket (RTIInternational/teehr-hub#525).
#
# Replaces the hand-made ciroh-rti-hefs-data bucket in us-east-2, which the
# region move left behind. hefs-fews-hub downloads RFC configurations from
# HEFS_FEWS/ (and Jupyter users read the rest), so cluster reads stay in-region.
#
# Only created when var.hefs_data_bucket is set (the use1 stack): this root is
# applied for every regional stack, and S3 names are global.
#
# Settings mirror the old bucket: anyone can GetObject (data is public, URLs
# are shared), listing needs credentials, ACLs are off. Writes are by hand, by
# members of the writers group (hefs-data-policies.tf). The copy from the old
# bucket is docs/hefs-bucket-move.md.

locals {
  hefs_data_enabled = var.hefs_data_bucket != null
}

resource "aws_s3_bucket" "hefs_data" {
  count  = local.hefs_data_enabled ? 1 : 0
  bucket = var.hefs_data_bucket

  tags = {
    Name        = var.hefs_data_bucket
    Environment = var.environment
    Project     = var.project_name
  }
}

# Public reads come from the bucket policy, so only ACLs are blocked.
resource "aws_s3_bucket_public_access_block" "hefs_data" {
  count  = local.hefs_data_enabled ? 1 : 0
  bucket = aws_s3_bucket.hefs_data[0].id

  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_ownership_controls" "hefs_data" {
  count  = local.hefs_data_enabled ? 1 : 0
  bucket = aws_s3_bucket.hefs_data[0].id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "hefs_data" {
  count  = local.hefs_data_enabled ? 1 : 0
  bucket = aws_s3_bucket.hefs_data[0].id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Hand uploads of large files are multipart; an interrupted one otherwise
# keeps billing for its parts.
resource "aws_s3_bucket_lifecycle_configuration" "hefs_data" {
  count  = local.hefs_data_enabled ? 1 : 0
  bucket = aws_s3_bucket.hefs_data[0].id

  rule {
    id     = "abort-incomplete-multipart-uploads"
    status = "Enabled"
    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

data "aws_iam_policy_document" "hefs_data_public_read" {
  count = local.hefs_data_enabled ? 1 : 0

  statement {
    sid       = "PublicRead"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.hefs_data[0].arn}/*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }
  }
}

resource "aws_s3_bucket_policy" "hefs_data" {
  count  = local.hefs_data_enabled ? 1 : 0
  bucket = aws_s3_bucket.hefs_data[0].id
  policy = data.aws_iam_policy_document.hefs_data_public_read[0].json

  # S3 rejects a public policy until the access block allows one.
  depends_on = [aws_s3_bucket_public_access_block.hefs_data]
}

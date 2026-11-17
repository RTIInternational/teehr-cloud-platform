resource "aws_s3_bucket" "teehr_iceberg_warehouse" {
  bucket = var.iceberg_warehouse_bucket

  tags = {
    Name        = var.iceberg_warehouse_bucket
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_s3_bucket_public_access_block" "teehr_iceberg_warehouse_public_access_block" {
  bucket = aws_s3_bucket.teehr_iceberg_warehouse.id

  block_public_acls   = true
  block_public_policy = true
  # block_public_policy      = false
  ignore_public_acls      = true
  restrict_public_buckets = true
  # restrict_public_buckets  = false
}

resource "aws_s3_bucket" "teehr_icechunk_warehouse" {
  bucket = var.icechunk_warehouse_bucket

  tags = {
    Name        = var.icechunk_warehouse_bucket
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_s3_bucket_public_access_block" "teehr_icechunk_warehouse_public_access_block" {
  bucket = aws_s3_bucket.teehr_icechunk_warehouse.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# resource "aws_s3_bucket_policy" "public_read" {
#   bucket = aws_s3_bucket.teehr_iceberg_warehouse.id

#   policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       {
#         Effect = "Allow"
#         Principal = "*"
#         Action = "s3:GetObject"
#         Resource = "${aws_s3_bucket.teehr_iceberg_warehouse.arn}/*"
#       }
#     ]
#   })
# }

# Postgres backups (teehr-cloud-core db-backups). Versioned, so a backup can't be
# destroyed by overwriting or deleting it; expired after var.db_backup_retention_days.
resource "aws_s3_bucket" "teehr_db_backups" {
  bucket = var.db_backup_bucket

  tags = {
    Name        = var.db_backup_bucket
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_s3_bucket_public_access_block" "teehr_db_backups_public_access_block" {
  bucket = aws_s3_bucket.teehr_db_backups.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "teehr_db_backups" {
  bucket = aws_s3_bucket.teehr_db_backups.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "teehr_db_backups" {
  bucket = aws_s3_bucket.teehr_db_backups.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "teehr_db_backups" {
  bucket = aws_s3_bucket.teehr_db_backups.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "teehr_db_backups" {
  bucket     = aws_s3_bucket.teehr_db_backups.id
  depends_on = [aws_s3_bucket_versioning.teehr_db_backups]

  rule {
    id     = "expire-old-backups"
    status = "Enabled"
    # Only the dumps; anything else stored here later isn't expired by this rule.
    filter {
      prefix = "postgres/"
    }

    expiration {
      days = var.db_backup_retention_days
    }
    noncurrent_version_expiration {
      noncurrent_days = 7
    }
    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }
}

# Upload staging (teehr-cloud-core control-plane): files users upload, waiting to be
# inspected and loaded. Private; written only through URLs the control plane signs.
# Short-lived by design: expired after var.upload_staging_retention_days.
resource "aws_s3_bucket" "upload_staging" {
  bucket = var.upload_staging_bucket

  tags = {
    Name        = var.upload_staging_bucket
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_s3_bucket_public_access_block" "upload_staging" {
  bucket = aws_s3_bucket.upload_staging.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "upload_staging" {
  bucket = aws_s3_bucket.upload_staging.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "upload_staging" {
  bucket = aws_s3_bucket.upload_staging.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "upload_staging" {
  bucket = aws_s3_bucket.upload_staging.id

  rule {
    id     = "expire-staged-uploads"
    status = "Enabled"
    filter {}

    expiration {
      days = var.upload_staging_retention_days
    }
    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }
}

# Browsers PUT files straight to the bucket with a presigned URL, so the web origins
# that upload need CORS. None configured: no CORS rule (CLI/SDK uploads still work).
resource "aws_s3_bucket_cors_configuration" "upload_staging" {
  count  = length(var.upload_cors_origins) > 0 ? 1 : 0
  bucket = aws_s3_bucket.upload_staging.id

  cors_rule {
    allowed_methods = ["PUT"]
    allowed_origins = var.upload_cors_origins
    allowed_headers = ["*"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }
}

# HEFS-FEWS data (RTIInternational/teehr-hub#525): replaces the hand-made us-east-2
# ciroh-rti-hefs-data. Public: anyone can GetObject (URLs are shared), listing needs
# credentials. Written by hand by the writers group (hefs-data-policies.tf).
# Only created when var.hefs_data_bucket is set (use1): S3 names are global.
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

# Hand uploads of large files are multipart; an interrupted one otherwise keeps
# billing for its parts.
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

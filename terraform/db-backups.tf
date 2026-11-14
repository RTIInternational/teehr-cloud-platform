# Postgres backups (teehr-cloud-core/db-backups, teehr-cloud-core#173).
#
# Nightly pg_dump archives of the in-cluster databases (app, keycloak, polaris,
# prefect) land under s3://<cluster>-db-backups/postgres/<db>/YYYY/MM/DD/.
#
# The db-backup service account can only add backups: it can write and list under
# postgres/, but not read or delete. With versioning on, a compromised backup pod
# can't destroy existing backups either. Restores are done by an operator with
# their own credentials.

variable "db_backup_retention_days" {
  type        = number
  default     = 35
  description = <<-EOT
  Days to keep each Postgres backup. Older dumps, and overwritten or deleted
  versions after 7 days, are expired.
  EOT
}

resource "aws_s3_bucket" "db_backups" {
  bucket = "${local.cluster_name}-db-backups"

  tags = {
    Name        = "${local.cluster_name}-db-backups"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_s3_bucket_public_access_block" "db_backups" {
  bucket = aws_s3_bucket.db_backups.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "db_backups" {
  bucket = aws_s3_bucket.db_backups.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "db_backups" {
  bucket = aws_s3_bucket.db_backups.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "db_backups" {
  bucket = aws_s3_bucket.db_backups.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "db_backups" {
  bucket     = aws_s3_bucket.db_backups.id
  depends_on = [aws_s3_bucket_versioning.db_backups]

  rule {
    id     = "expire-old-backups"
    status = "Enabled"
    filter {}

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

data "aws_iam_policy_document" "db_backup_trust_policy" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:sub"
      values   = ["system:serviceaccount:teehr-hub:db-backup"]
    }
  }
}

data "aws_iam_policy_document" "db_backup_write" {
  # Upload (streamed, so multipart) under postgres/ only.
  statement {
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:AbortMultipartUpload",
      "s3:ListMultipartUploadParts",
    ]
    resources = ["${aws_s3_bucket.db_backups.arn}/postgres/*"]
  }

  # List, so a run can confirm its upload landed.
  statement {
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.db_backups.arn]
    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["postgres/*"]
    }
  }
}

resource "aws_iam_role" "db_backup_irsa" {
  name               = "${local.cluster_name}-db-backup-irsa"
  assume_role_policy = data.aws_iam_policy_document.db_backup_trust_policy.json
  tags = {
    "teehr-hub/role" = "db-backup"
  }
}

resource "aws_iam_role_policy" "db_backup_write" {
  name   = "${local.cluster_name}-db-backup-write"
  role   = aws_iam_role.db_backup_irsa.id
  policy = data.aws_iam_policy_document.db_backup_write.json
}

output "db_backup_bucket" {
  value       = aws_s3_bucket.db_backups.bucket
  description = "Bucket for Postgres backups (teehr-cloud-core db-backups)"
}

output "db_backup_role_arn" {
  value       = aws_iam_role.db_backup_irsa.arn
  description = "IRSA role for the db-backup service account: write-only to the backup bucket"
}

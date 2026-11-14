# Postgres backup access policies.
#
# Policies only - no role attachments (see db-backup-irsa.tf). Write-only: a
# backup can be added under postgres/ but not read or deleted, so a compromised
# backup pod can't read the dumps or destroy them. Restores use an operator's own
# credentials.

data "aws_iam_policy_document" "db_backup_write" {
  # Upload (streamed, so multipart) under postgres/ only.
  statement {
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:AbortMultipartUpload",
      "s3:ListMultipartUploadParts",
    ]
    resources = ["${aws_s3_bucket.teehr_db_backups.arn}/postgres/*"]
  }

  # List, so a run can confirm its upload landed.
  statement {
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.teehr_db_backups.arn]
    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["postgres/*"]
    }
  }
}

resource "aws_iam_policy" "db_backup_write" {
  name   = "${local.cluster_name}-db-backup-write"
  policy = data.aws_iam_policy_document.db_backup_write.json
}

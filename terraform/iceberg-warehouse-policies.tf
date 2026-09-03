# Iceberg warehouse access policies.
#
# Policies only — no role attachments, so several roles can share one policy
# (see iceberg-s3-warehouse-irsa.tf and prefect-job-irsa.tf).
#
# Note: the read-only policy here grants warehouse reads. It is distinct from
# the HEFS-scoped policy in iceberg-s3-warehouse-readonly-irsa.tf, whose name
# is legacy and whose scope is external data only.

data "aws_iam_policy_document" "iceberg_s3_warehouse_rw" {
  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket"
    ]
    resources = [
      aws_s3_bucket.teehr_iceberg_warehouse.arn,
      "${aws_s3_bucket.teehr_iceberg_warehouse.arn}/*"
    ]
  }
}

resource "aws_iam_policy" "iceberg_s3_warehouse_rw" {
  name   = "teehr-hub-iceberg-s3-warehouse-rw"
  policy = data.aws_iam_policy_document.iceberg_s3_warehouse_rw.json
}

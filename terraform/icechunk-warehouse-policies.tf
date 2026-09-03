# Icechunk warehouse access policies.
#
# Policies only — no role attachments. Icechunk stores are plain S3 zarr data,
# not Iceberg tables, so Polaris cannot vend credentials for them; consumers
# hold their own narrowly-scoped IRSA roles and attach these policies
# themselves (see prefect-job-irsa.tf and xpublish-api-irsa.tf).

data "aws_iam_policy_document" "icechunk_s3_warehouse_rw" {
  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket"
    ]
    resources = [
      aws_s3_bucket.teehr_icechunk_warehouse.arn,
      "${aws_s3_bucket.teehr_icechunk_warehouse.arn}/*"
    ]
  }
}

resource "aws_iam_policy" "icechunk_s3_warehouse_rw" {
  name   = "teehr-hub-icechunk-s3-warehouse-rw"
  policy = data.aws_iam_policy_document.icechunk_s3_warehouse_rw.json
}

data "aws_iam_policy_document" "icechunk_s3_warehouse_readonly" {
  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:ListBucket"
    ]
    resources = [
      aws_s3_bucket.teehr_icechunk_warehouse.arn,
      "${aws_s3_bucket.teehr_icechunk_warehouse.arn}/*"
    ]
  }
}

resource "aws_iam_policy" "icechunk_s3_warehouse_readonly" {
  name   = "teehr-hub-icechunk-s3-warehouse-readonly"
  policy = data.aws_iam_policy_document.icechunk_s3_warehouse_readonly.json
}

# Trusted only by Polaris's own IRSA role. Trino, Spark, and Prefect no
# longer assume this role directly — they access warehouse data exclusively
# through Polaris-vended, per-request scoped credentials, and Polaris is the
# one that assumes this role (via STS AssumeRole) to mint them.
data "aws_iam_policy_document" "iceberg_s3_warehouse_trust_policy" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.polaris_irsa.arn]
    }
  }
}

resource "aws_iam_role" "iceberg_s3_warehouse_irsa" {
  name               = "teehr-hub-iceberg-s3-warehouse-irsa"
  assume_role_policy = data.aws_iam_policy_document.iceberg_s3_warehouse_trust_policy.json
  tags = {
    "teehr-hub/role" = "iceberg-s3-warehouse"
  }
}

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

resource "aws_iam_role_policy_attachment" "iceberg_s3_warehouse_rw" {
  role       = aws_iam_role.iceberg_s3_warehouse_irsa.name
  policy_arn = aws_iam_policy.iceberg_s3_warehouse_rw.arn
}
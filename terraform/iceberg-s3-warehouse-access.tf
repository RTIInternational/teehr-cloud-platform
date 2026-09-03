# The Iceberg warehouse data-access role. It has no OIDC/IRSA trust of its
# own — only Polaris's IRSA role (aws_iam_role.polaris_irsa) may assume it.
# Trino, Spark, and Jupyter no longer reach warehouse data directly; they
# receive Polaris-vended, per-request scoped credentials, and Polaris is the
# one that assumes this role (via STS AssumeRole) to mint them.
#
# The one exception is prefect-job, which keeps a direct IRSA role for
# non-catalog work (see prefect-job-irsa.tf) and attaches the same RW policy.
# Policy documents live in iceberg-warehouse-policies.tf.

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

resource "aws_iam_role" "iceberg_s3_warehouse_access" {
  name               = "teehr-hub-iceberg-s3-warehouse-access"
  assume_role_policy = data.aws_iam_policy_document.iceberg_s3_warehouse_trust_policy.json
  tags = {
    "teehr-hub/role" = "iceberg-s3-warehouse"
  }
}

resource "aws_iam_role_policy_attachment" "iceberg_s3_warehouse_rw" {
  role       = aws_iam_role.iceberg_s3_warehouse_access.name
  policy_arn = aws_iam_policy.iceberg_s3_warehouse_rw.arn
}

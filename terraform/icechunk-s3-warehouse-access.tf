# The Icechunk warehouse data-access role. It has no OIDC/IRSA trust of its
# own — only xpublish-api's IRSA role (aws_iam_role.xpublish_api_irsa) may
# assume it. xpublish-api assumes it (via STS AssumeRole) with a session
# policy scoped to the repos a user may read, and vends those short-lived,
# read-only credentials to notebooks. Access rules live in teehr-cloud-core
# docs/icechunk-access-control.md. Policy documents live in
# icechunk-warehouse-policies.tf.

data "aws_iam_policy_document" "icechunk_s3_warehouse_trust_policy" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.xpublish_api_irsa.arn]
    }
  }
}

resource "aws_iam_role" "icechunk_s3_warehouse_access" {
  name               = "${local.cluster_name}-icechunk-s3-warehouse-access"
  assume_role_policy = data.aws_iam_policy_document.icechunk_s3_warehouse_trust_policy.json
  tags = {
    "teehr-hub/role" = "icechunk-s3-warehouse"
  }
}

resource "aws_iam_role_policy_attachment" "icechunk_s3_warehouse_readonly" {
  role       = aws_iam_role.icechunk_s3_warehouse_access.name
  policy_arn = aws_iam_policy.icechunk_s3_warehouse_readonly.arn
}

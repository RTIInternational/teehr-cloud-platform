# Read-only access for the Jupyter service account to external, non-warehouse
# data only (e.g. ciroh-rti-hefs-data). Warehouse access no longer goes
# through this role for anyone — Spark was removed, and Jupyter's own
# Iceberg warehouse reads now go through Polaris-vended credentials like
# every other client. This role name is legacy; its scope is now HEFS-only.
data "aws_iam_policy_document" "iceberg_s3_warehouse_readonly_trust_policy" {
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
      values = [
        "system:serviceaccount:teehr-hub:jupyter"
      ]
    }
  }
}

resource "aws_iam_role" "iceberg_s3_warehouse_readonly_irsa" {
  name               = "teehr-hub-iceberg-s3-warehouse-readonly-irsa"
  assume_role_policy = data.aws_iam_policy_document.iceberg_s3_warehouse_readonly_trust_policy.json
  tags = {
    "teehr-hub/role" = "jupyter-external-data-readonly"
  }
}

data "aws_iam_policy_document" "iceberg_s3_warehouse_readonly" {
  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:ListBucket"
    ]
    resources = [
      "arn:aws:s3:::ciroh-rti-hefs-data",
      "arn:aws:s3:::ciroh-rti-hefs-data/*"
    ]
  }
}

resource "aws_iam_policy" "iceberg_s3_warehouse_readonly" {
  name   = "teehr-hub-iceberg-s3-warehouse-readonly"
  policy = data.aws_iam_policy_document.iceberg_s3_warehouse_readonly.json
}

resource "aws_iam_role_policy_attachment" "iceberg_s3_warehouse_readonly" {
  role       = aws_iam_role.iceberg_s3_warehouse_readonly_irsa.name
  policy_arn = aws_iam_policy.iceberg_s3_warehouse_readonly.arn
}
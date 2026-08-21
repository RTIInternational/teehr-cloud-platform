# IRSA for Polaris — its own AWS identity, used to assume the Iceberg
# warehouse data-access role (teehr-hub-iceberg-s3-warehouse-irsa) and vend
# scoped, short-lived S3 credentials to catalog clients (Trino, Spark,
# Prefect, Jupyter) via the Iceberg REST catalog protocol. Polaris is the
# only service in the cluster with standing access to the warehouse bucket.

data "aws_iam_policy_document" "polaris_trust_policy" {
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
      values   = ["system:serviceaccount:teehr-hub:polaris"]
    }
  }
}

resource "aws_iam_role" "polaris_irsa" {
  name               = "teehr-hub-polaris-irsa"
  assume_role_policy = data.aws_iam_policy_document.polaris_trust_policy.json
  tags = {
    "teehr-hub/role" = "polaris"
  }
}

data "aws_iam_policy_document" "polaris_assume_warehouse_role" {
  statement {
    effect    = "Allow"
    actions   = ["sts:AssumeRole"]
    resources = [aws_iam_role.iceberg_s3_warehouse_irsa.arn]
  }
}

resource "aws_iam_role_policy" "polaris_assume_warehouse_role" {
  name   = "teehr-hub-polaris-assume-warehouse-role"
  role   = aws_iam_role.polaris_irsa.name
  policy = data.aws_iam_policy_document.polaris_assume_warehouse_role.json
}

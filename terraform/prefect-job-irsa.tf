# IRSA for the prefect-job service account, used by Prefect flow-run pods and
# the Spark executors they launch.
#
# This is a deliberate carve-out from the Polaris credential-vending model.
# Iceberg catalog access does NOT need this role — flow pods run with
# POLARIS_USE_STS=true and receive scoped, short-lived S3 credentials from
# Polaris. This role exists for the non-catalog work Prefect does directly:
# icechunk (plain S3 zarr, which Polaris cannot vend for) and any future
# direct-bucket access. The Iceberg RW attachment is a safety net so a
# workflow that bypasses the catalog still functions.
#
# Public source data (e.g. ciroh-community-ngen-datastream) is read
# anonymously and needs no credentials at all.

data "aws_iam_policy_document" "prefect_job_trust_policy" {
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
      values   = ["system:serviceaccount:teehr-hub:prefect-job"]
    }
  }
}

resource "aws_iam_role" "prefect_job_irsa" {
  name               = "teehr-hub-prefect-job-irsa"
  assume_role_policy = data.aws_iam_policy_document.prefect_job_trust_policy.json
  tags = {
    "teehr-hub/role" = "prefect-job"
  }
}

resource "aws_iam_role_policy_attachment" "prefect_job_icechunk_rw" {
  role       = aws_iam_role.prefect_job_irsa.name
  policy_arn = aws_iam_policy.icechunk_s3_warehouse_rw.arn
}

resource "aws_iam_role_policy_attachment" "prefect_job_iceberg_rw" {
  role       = aws_iam_role.prefect_job_irsa.name
  policy_arn = aws_iam_policy.iceberg_s3_warehouse_rw.arn
}

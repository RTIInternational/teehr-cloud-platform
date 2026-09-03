# IRSA for the xpublish-api service account — the gridded-data backend.
#
# xpublish-api reads icechunk zarr stores only; it never touches the Iceberg
# warehouse or external HEFS data, so it gets icechunk read-only and nothing
# else. Icechunk is plain S3 data rather than Iceberg tables, so Polaris
# cannot vend credentials for it and this direct attachment is required.
#
# Read-only is deliberate: xpublish-api is a public-facing read API. Note that
# provider.py's _ensure_repo_initialized() will try to CREATE a missing
# icechunk repo, which this role cannot do. New repos must be created by a
# writer (the Prefect ingest, which holds icechunk RW) before being added to
# var.icechunk.repos. Widen this to icechunk_s3_warehouse_rw only if you
# decide xpublish-api should self-initialize repos.

data "aws_iam_policy_document" "xpublish_api_trust_policy" {
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
      values   = ["system:serviceaccount:teehr-hub:xpublish-api"]
    }
  }
}

resource "aws_iam_role" "xpublish_api_irsa" {
  name               = "teehr-hub-xpublish-api-irsa"
  assume_role_policy = data.aws_iam_policy_document.xpublish_api_trust_policy.json
  tags = {
    "teehr-hub/role" = "xpublish-api"
  }
}

resource "aws_iam_role_policy_attachment" "xpublish_api_icechunk_readonly" {
  role       = aws_iam_role.xpublish_api_irsa.name
  policy_arn = aws_iam_policy.icechunk_s3_warehouse_readonly.arn
}

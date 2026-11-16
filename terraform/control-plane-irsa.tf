# IRSA for the teehr-control-plane service account (teehr-cloud-core control-plane).
#
# Only the upload staging bucket (control-plane-policies.tf). The control plane never
# touches warehouse data with its own identity: table reads and writes go through
# Polaris as the calling user, with credentials Polaris vends.

data "aws_iam_policy_document" "control_plane_trust_policy" {
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
      values   = ["system:serviceaccount:teehr-hub:teehr-control-plane"]
    }
  }
}

resource "aws_iam_role" "control_plane_irsa" {
  name               = "${local.cluster_name}-control-plane-irsa"
  assume_role_policy = data.aws_iam_policy_document.control_plane_trust_policy.json
  tags = {
    "teehr-hub/role" = "control-plane"
  }
}

resource "aws_iam_role_policy_attachment" "control_plane_upload_staging" {
  role       = aws_iam_role.control_plane_irsa.name
  policy_arn = aws_iam_policy.control_plane_upload_staging.arn
}

# IRSA for the db-backup service account - the nightly pg_dump CronJobs in
# teehr-cloud-core/db-backups (app, keycloak, polaris, prefect databases).
#
# Write-only to the backup bucket (db-backup-policies.tf); no other S3 access.

data "aws_iam_policy_document" "db_backup_trust_policy" {
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
      values   = ["system:serviceaccount:teehr-hub:db-backup"]
    }
  }
}

resource "aws_iam_role" "db_backup_irsa" {
  name               = "${local.cluster_name}-db-backup-irsa"
  assume_role_policy = data.aws_iam_policy_document.db_backup_trust_policy.json
  tags = {
    "teehr-hub/role" = "db-backup"
  }
}

resource "aws_iam_role_policy_attachment" "db_backup_write" {
  role       = aws_iam_role.db_backup_irsa.name
  policy_arn = aws_iam_policy.db_backup_write.arn
}

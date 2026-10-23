resource "aws_iam_group" "teehr_hub_admins" {
  name = "TeehrHubAdmins"
}

resource "aws_iam_group_policy" "teehr_hub_admins_assume_role" {
  name  = "TeehrHubAdminsAssumeRole"
  group = aws_iam_group.teehr_hub_admins.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "sts:AssumeRole"
        Resource = aws_iam_role.teehr_hub_admin.arn
      }
    ]
  })
}

resource "aws_iam_role" "teehr_hub_admin" {
  name = "${var.name}-teehr-hub-admin"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = [
            "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root",
          ]
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
  tags = {
    "teehr-hub/role" = "admin"
  }
}

# GitHub Actions OIDC Provider
resource "aws_iam_openid_connect_provider" "github_actions" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]

  tags = {
    "teehr-hub/purpose" = "github-actions-oidc"
  }
}



# IAM role for GitHub Actions to deploy with Garden
resource "aws_iam_role" "github_actions_garden_deploy" {
  name = "${var.name}-github-actions-garden-deploy"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github_actions.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "token.actions.githubusercontent.com:sub" = "repo:RTIInternational/teehr-hub:*"
          }
        }
      }
    ]
  })

  tags = {
    "teehr-hub/role"    = "github-actions-garden-deploy"
    "teehr-hub/purpose" = "cicd"
  }
}

# Policy for GitHub Actions Garden deploy role
resource "aws_iam_role_policy" "github_actions_garden_deploy" {
  name = "github-actions-garden-deploy-policy"
  role = aws_iam_role.github_actions_garden_deploy.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "eks:DescribeCluster",
          "eks:AccessKubernetesApi"
        ]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = "sts:AssumeRole"
        Resource = aws_iam_role.teehr_hub_admin.arn
      }
    ]
  })
}
# IAM roles for the Terraform workflow (.github/workflows/terraform-use1.yml).
# Each is trusted only by jobs in one GitHub environment: the plan job
# (terraform-plan) and the apply job (production, which has required reviewers).
locals {
  terraform_state_bucket = "teehr-terraform-state"
  terraform_repo         = "repo:RTIInternational/teehr-cloud-platform"
}

data "aws_iam_policy_document" "github_actions_terraform_trust" {
  for_each = toset(["terraform-plan", "production"])

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github_actions.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["${local.terraform_repo}:environment:${each.key}"]
    }
  }
}

# Plan: read-only, plus writing the state lock and the saved plan file.
resource "aws_iam_role" "github_actions_terraform_plan" {
  name               = "${var.name}-github-actions-terraform-plan"
  assume_role_policy = data.aws_iam_policy_document.github_actions_terraform_trust["terraform-plan"].json

  tags = {
    "teehr-hub/role"    = "github-actions-terraform-plan"
    "teehr-hub/purpose" = "cicd"
  }
}

resource "aws_iam_role_policy_attachment" "github_actions_terraform_plan_readonly" {
  role       = aws_iam_role.github_actions_terraform_plan.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

data "aws_iam_policy_document" "github_actions_terraform_plan_state" {
  statement {
    effect  = "Allow"
    actions = ["s3:PutObject", "s3:DeleteObject"]
    resources = [
      "arn:aws:s3:::${local.terraform_state_bucket}/*.tflock",
      "arn:aws:s3:::${local.terraform_state_bucket}/plans/*",
    ]
  }
}

resource "aws_iam_role_policy" "github_actions_terraform_plan_state" {
  name   = "terraform-state-lock-and-plans"
  role   = aws_iam_role.github_actions_terraform_plan.id
  policy = data.aws_iam_policy_document.github_actions_terraform_plan_state.json
}

# Apply: admin, gated by the production environment's reviewers. A full
# apply can roll every node group, so sessions last up to 4 h.
resource "aws_iam_role" "github_actions_terraform_apply" {
  name                 = "${var.name}-github-actions-terraform-apply"
  assume_role_policy   = data.aws_iam_policy_document.github_actions_terraform_trust["production"].json
  max_session_duration = 14400

  tags = {
    "teehr-hub/role"    = "github-actions-terraform-apply"
    "teehr-hub/purpose" = "cicd"
  }
}

resource "aws_iam_role_policy_attachment" "github_actions_terraform_apply_admin" {
  role       = aws_iam_role.github_actions_terraform_apply.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

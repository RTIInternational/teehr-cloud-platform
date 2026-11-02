resource "aws_ecr_repository" "repos" {
  for_each = { for repo in concat(local.ecr_repos, var.additional_ecr_repos) : repo.name => repo }
  name     = each.value.name
  image_scanning_configuration {
    scan_on_push = true
  }
  image_tag_mutability = "MUTABLE"
  force_delete         = true
  encryption_configuration {
    encryption_type = "KMS"
  }
  lifecycle {
    prevent_destroy = false
  }
  tags = local.tags
}

resource "aws_ecr_lifecycle_policy" "repos" {
  for_each   = aws_ecr_repository.repos
  repository = each.key

  policy = jsonencode({
    rules = [
      # Untagged images are superseded build pushes; nothing deploys them, but
      # Inspector keeps rescanning and reporting them.
      {
        rulePriority = 1
        description  = "Expire untagged images after 1 day"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 1
        }
        action = {
          type = "expire"
        }
      },
      # Garden tags builds v-<hash>. Counting only those keeps _buildcache and
      # untagged cache manifests from pushing deployed images out.
      {
        rulePriority = 2
        description  = "Keep only the last N images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["v-"]
          countType     = "imageCountMoreThan"
          countNumber   = lookup({ for repo in local.ecr_repos : repo.name => repo.max_image_count }, each.key, 10)
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# Registry-wide, per region. Continuous scanning has Inspector rescan images
# when new CVEs are published, not only on push, so long-running images (e.g.
# the Spark executor) keep current findings. How long an image keeps being
# rescanned after its last push or pull is the Inspector account setting
# (currently 7 days), so images still pulled by running pods stay covered.
resource "aws_ecr_registry_scanning_configuration" "this" {
  scan_type = "ENHANCED"

  rule {
    scan_frequency = "CONTINUOUS_SCAN"
    repository_filter {
      filter      = "*"
      filter_type = "WILDCARD"
    }
  }
}

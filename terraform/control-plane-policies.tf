# Upload staging access for the control plane.
#
# Policies only - no role attachments (see control-plane-irsa.tf). The control plane
# signs the URLs users PUT their files to and its load jobs GET them from (a
# presigned URL acts with the signer's permissions), reads the start of a file to
# inspect it, and deletes files with their upload or project.

data "aws_iam_policy_document" "control_plane_upload_staging" {
  statement {
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:DeleteObject",
      "s3:AbortMultipartUpload",
    ]
    resources = ["${aws_s3_bucket.upload_staging.arn}/*"]
  }

  # List, to delete a project's staged files by prefix.
  statement {
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.upload_staging.arn]
  }
}

resource "aws_iam_policy" "control_plane_upload_staging" {
  name   = "${local.cluster_name}-control-plane-upload-staging"
  policy = data.aws_iam_policy_document.control_plane_upload_staging.json
}

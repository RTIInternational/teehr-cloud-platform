# Write access to the HEFS-FEWS data bucket (hefs-data.tf).
#
# The data is maintained by hand (aws s3 cp/sync from people's own IAM users),
# not by a workflow, so access goes through a group. Membership isn't managed
# here: add users with `aws iam add-user-to-group`. Reads need nothing (the
# bucket is public), except listing, which the Jupyter role already has
# (iceberg-s3-warehouse-readonly-irsa.tf).

data "aws_iam_policy_document" "hefs_data_write" {
  count = local.hefs_data_enabled ? 1 : 0

  statement {
    sid       = "List"
    effect    = "Allow"
    actions   = ["s3:ListBucket", "s3:ListBucketMultipartUploads", "s3:GetBucketLocation"]
    resources = [aws_s3_bucket.hefs_data[0].arn]
  }

  # Delete as well as put: configurations are replaced wholesale (back up an
  # RFC folder, then re-upload it), which `aws s3 sync --delete` needs.
  statement {
    sid    = "ReadWriteObjects"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:AbortMultipartUpload",
      "s3:ListMultipartUploadParts",
    ]
    resources = ["${aws_s3_bucket.hefs_data[0].arn}/*"]
  }
}

resource "aws_iam_policy" "hefs_data_write" {
  count  = local.hefs_data_enabled ? 1 : 0
  name   = "${local.cluster_name}-hefs-data-write"
  policy = data.aws_iam_policy_document.hefs_data_write[0].json
}

resource "aws_iam_group" "hefs_data_writers" {
  count = local.hefs_data_enabled ? 1 : 0
  name  = "${local.cluster_name}-hefs-data-writers"
}

resource "aws_iam_group_policy_attachment" "hefs_data_writers" {
  count      = local.hefs_data_enabled ? 1 : 0
  group      = aws_iam_group.hefs_data_writers[0].name
  policy_arn = aws_iam_policy.hefs_data_write[0].arn
}

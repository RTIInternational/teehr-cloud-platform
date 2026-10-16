# EKS stopped marking gp2 as the default StorageClass for clusters created on
# 1.30+, so PVCs without a storageClassName stay Pending there. New stacks get
# a gp3 default through the EBS CSI driver. The us-east-2 cluster predates
# that change and keeps gp2 as its default.
resource "kubernetes_storage_class_v1" "gp3" {
  count = var.create_default_storage_class ? 1 : 0

  metadata {
    name = "gp3"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" = "true"
    }
  }

  storage_provisioner    = "ebs.csi.aws.com"
  reclaim_policy         = "Delete"
  volume_binding_mode    = "WaitForFirstConsumer"
  allow_volume_expansion = true

  parameters = {
    type   = "gp3"
    fsType = "ext4"
  }
}

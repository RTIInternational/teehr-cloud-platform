locals {
  # cluster-autoscaler ships a release series per Kubernetes minor version, and AWS
  # requires the running image to match the control plane minor. The chart pins a
  # single default tag, so select the tag from the cluster version instead.
  cluster_autoscaler_image_tags = {
    "1.33" = "v1.33.6"
    "1.34" = "v1.34.5"
    "1.35" = "v1.35.2"
    "1.36" = "v1.36.1"
  }
}

resource "helm_release" "cluster_autoscaler" {
  name       = "cluster-autoscaler"
  repository = "https://kubernetes.github.io/autoscaler"
  chart      = "cluster-autoscaler"
  version    = "9.59.0"
  namespace  = "kube-system"

  values = [yamlencode({
    autoDiscovery = {
      clusterName = var.cluster_name
    }
    image = {
      tag = local.cluster_autoscaler_image_tags[var.cluster_version]
    }
    awsRegion = var.region
    rbac = {
      create = true
      serviceAccount = {
        name   = "cluster-autoscaler"
        create = true
        annotations = {
          "eks.amazonaws.com/role-arn" = aws_iam_role.cluster_autoscaler_irsa.arn
        }
      }
    }
    extraArgs = {
      "scale-down-unneeded-time"      = "5m"
      "skip-nodes-with-local-storage" = "false"
      "balance-similar-node-groups"   = "true"
      expander                        = "least-waste"
    }
  })]
}

locals {
  node_termination_manifest_documents = [
    for doc in split("\n---\n", file("${path.module}/manifests/node-termination-handler.yaml")) :
    trimspace(doc)
    if length(regexall("(?m)^\\s*[^#\\s].*$", doc)) > 0
  ]

  node_termination_manifest_objects = [
    for doc in local.node_termination_manifest_documents : yamldecode(doc)
  ]
}

resource "kubernetes_manifest" "node_termination_handler" {
  for_each = {
    for obj in local.node_termination_manifest_objects :
    "${obj.kind}:${lookup(obj.metadata, "namespace", "cluster")}:${obj.metadata.name}" => obj
  }

  manifest = each.value

  field_manager {
    force_conflicts = true
  }
}

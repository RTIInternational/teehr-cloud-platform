resource "helm_release" "cert_manager" {
  name             = "cert-manager"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  version          = "v1.21.2"
  namespace        = "cert-manager"
  create_namespace = false

  values = [yamlencode({
    # installCRDs is deprecated as of chart v1.15; crds.keep leaves the CRDs
    # (and therefore the Certificate resources) in place on an uninstall.
    crds = {
      enabled = true
      keep    = true
    }
  })]
}

locals {
  cert_manager_manifest_documents = [
    for doc in split("\n---\n", file("${path.module}/manifests/cert-manager.yaml")) :
    trimspace(doc)
    if length(regexall("(?m)^\\s*[^#\\s].*$", doc)) > 0
  ]

  cert_manager_manifest_objects = [
    for doc in local.cert_manager_manifest_documents : yamldecode(doc)
  ]
}

resource "kubernetes_manifest" "cert_manager" {
  for_each = {
    for obj in local.cert_manager_manifest_objects :
    "${obj.kind}:${lookup(obj.metadata, "namespace", "cluster")}:${obj.metadata.name}" => obj
  }

  manifest = each.value

  depends_on = [helm_release.cert_manager]

  field_manager {
    force_conflicts = true
  }
}

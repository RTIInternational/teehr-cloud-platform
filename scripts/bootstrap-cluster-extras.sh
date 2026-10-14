#!/usr/bin/env bash
set -euo pipefail

# Applies the in-cluster pieces Terraform deliberately doesn't own, for a new
# regional stack (see docs/new-regional-stack.md):
#   pre   cert-manager namespace (helm_release uses create_namespace = false)
#         and the Contour CRDs from terraform/manifests/contour.yaml
#   post  the Contour certgen Job, which needs the projectcontour namespace and
#         RBAC that Terraform creates
#
# Usage: CONTEXT=<kube-context> ./scripts/bootstrap-cluster-extras.sh pre|post

STAGE="${1:-}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONTOUR_MANIFEST="$REPO_ROOT/terraform/manifests/contour.yaml"

if [[ -z "${CONTEXT:-}" ]]; then
  echo "ERROR: set CONTEXT to the new cluster's kube context" >&2
  exit 1
fi
kube=(kubectl --context "$CONTEXT")

# Prints the documents in contour.yaml of the given kind.
contour_docs() {
  python3 - "$CONTOUR_MANIFEST" "$1" <<'EOF'
import re, sys
path, kind = sys.argv[1], sys.argv[2]
docs = open(path).read().split("\n---\n")
print("\n---\n".join(d for d in docs if re.search(rf"(?m)^kind: {kind}\s*$", d)))
EOF
}

case "$STAGE" in
  pre)
    "${kube[@]}" create namespace cert-manager --dry-run=client -o yaml | "${kube[@]}" apply -f -
    contour_docs CustomResourceDefinition | "${kube[@]}" apply --server-side -f -
    ;;
  post)
    contour_docs Job | "${kube[@]}" apply -f -
    ;;
  *)
    echo "Usage: CONTEXT=<kube-context> $0 pre|post" >&2
    exit 1
    ;;
esac

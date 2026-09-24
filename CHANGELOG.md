# Changelog

## 2026-09-24

### Summary
- Upgraded the EKS control plane from Kubernetes 1.33 to 1.36, applied one minor version at a time.
- Bumped cluster-autoscaler, node-termination-handler and Contour to versions compatible with the new control plane.

### What Changed
- `cluster_version` moves 1.33 -> 1.34 -> 1.35 -> 1.36, one commit per hop.
- cluster-autoscaler chart 9.29.0 -> 9.59.0, with the image tag now selected from `var.cluster_version`.
- aws-node-termination-handler v1.22.0 -> v1.25.6.
- Contour re-vendored v1.33.0 -> v1.33.7.
- Added `docs/eks-upgrade.md` with the apply order, per-hop verification and rollback.

### Why
- 1.33 left standard support on 2026-07-29 and was billing at the extended-support rate. 1.36 carries standard support to 2027-08-02.
- cluster-autoscaler was pinned to v1.27.1, six minor versions behind the control plane.

### Known Gaps
- No released Contour version is tested against Kubernetes 1.35 or 1.36; Contour 1.33.7 covers 1.34/1.33/1.32. See `docs/eks-upgrade.md`.
- cert-manager remains on chart v1.12.0 and is being updated separately.

## 2026-07-07

### Summary
- Migrated terraform, contour, cert-manager and autoscaler for remote infrastructure components from `teehr-hub` to this repo.
- Current contour, cert-manager and autoscaler state were imported to terraform state without destroy and recreation.
- Consolidated operational guidance and separated migration history from day-to-day docs.

### What Changed
- Added Terraform for AWS resources from `teehr-hub`.
- Added Terraform for contour and cluster-autoscaler/node-termination-handler resources.
- Added contour import/adoption helper and stabilization updates for existing-cluster adoption.
- Updated migration and operational documentation structure (including migration notes split).
- Kept Terraform definitions aligned and cleaned up related migration script output.

### Why
- Split the application code from the platform code to allow the application to more cleanly be extended to other platforms. 

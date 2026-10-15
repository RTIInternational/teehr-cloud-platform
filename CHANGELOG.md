# Changelog

## Unreleased (us-east-1 stack)

### Summary
- Added the us-east-1 regional stack config (`teehr-hub-use1.tfvars`, `backends/use1.hcl`) and the runbook to
  build it next to us-east-2 (RTIInternational/teehr-hub#462).

### What Changed
- `teehr-hub-use1.tfvars`: cluster `teehr-hub-use1`, AZs led by us-east-1c (best spot placement score for the
  r5 family), buckets `teehr-iceberg-warehouse-use1` / `teehr-icechunk-warehouse-use1`.
- `cluster_creator_admin` variable: EKS access entry for whoever applies, needed by the kubernetes/helm
  providers on a new cluster.
- `scripts/bootstrap-cluster-extras.sh`: cert-manager namespace, Contour CRDs and certgen Job, which Terraform
  doesn't own.
- `staging_ingress` in `terraform/global/`: `*.<label>.teehr.rtiamanzi.org` for testing a stack before cutover.
- `ecr_registry` output; `ingress_elb_hostname` is null instead of an error before the load balancer exists.
- `docs/new-regional-stack.md`.

## Unreleased (parallel regional stacks)

### Summary
- Split account-wide resources into a separate `terraform/global/` root and made the regional root reusable for
  a second stack, ahead of the us-east-2 -> us-east-1 move (RTIInternational/teehr-hub#462). No resources are
  created, replaced or renamed in us-east-2.

### What Changed
- `terraform/global/`: admin and CI IAM, Route 53, CloudFront/ACM and the maintenance bucket, adopted with
  `import` blocks while `removed` blocks dropped them from the regional state; both were deleted after the
  2026-10-14 apply. The wildcard
  record now takes the Envoy ELB from `ingress_elb_hostname`/`ingress_elb_region` variables.
- Regional state is selected with `-backend-config=backends/<stack>.hcl`; both roots use S3 state locking.
- IAM names are prefixed with `cluster_name`; `legacy_iam_names` keeps the original unprefixed names for
  us-east-2. Warehouse bucket names and `azs` are variables; removed the unused `cluster_nodes_location`.
- New `ingress_elb_hostname` output on the regional root.

### Why
- IAM and S3 names are account- or globally-unique, so a second regional stack can't reuse them, and tearing down
  us-east-2 must not take DNS or CI with it.

## Unreleased (maintenance page)

### Summary
- Delegated `teehr.rtiamanzi.org` from Azure DNS to Route 53 and added a CloudFront/S3 maintenance page that a
  `maintenance_mode` variable switches the app hosts to.

### What Changed
- `terraform/dns.tf`: Route 53 zone, `*.teehr` alias to the Envoy ELB (or CloudFront in maintenance mode), and
  an always-on `status.teehr` alias.
- `terraform/maintenance.tf` + `terraform/maintenance/`: S3 bucket, us-east-1 wildcard ACM cert, CloudFront
  distribution and functions that return 503 (HTML for browsers, JSON for API clients), and a `status.json`
  for app banners.
- Added `docs/maintenance-page.md` with the two-step apply, Azure delegation and maintenance runbook.

### Why
- The cluster serves its own ingress and TLS, so nothing could tell users about planned outages, including the
  upcoming us-east-2 -> us-east-1 move (RTIInternational/teehr-hub#460).

## 2026-09-24 (cert-manager)

### Summary
- Upgraded cert-manager from chart v1.12.0 to v1.21.2 via uninstall and re-install.

### What Changed
- `terraform/cert-manager.tf` pins chart v1.21.2 and replaces the deprecated `installCRDs` value with `crds.enabled` / `crds.keep`.
- Added `docs/cert-manager-upgrade.md` with the procedure, pre-flight checks and rollback.

### Why
- cert-manager does not support jumping minor versions, and v1.12.0 (May 2023) predates Kubernetes 1.28, so it is well outside its tested range on the upgraded control plane. v1.21 is tested on Kubernetes 1.33 through 1.36.
- The v1.12 chart renders its CRDs without `helm.sh/resource-policy: keep`; `crds.keep` prevents a future uninstall from deleting every Certificate in the cluster.

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

### Applied
- All three hops applied and verified on 2026-09-24.
- Two DaemonSets failed the first apply with `Provider produced inconsistent result after apply` on `deprecated.daemonset.template.generation`. The writes had succeeded; re-running the apply converged. Open provider bug, unfixed in kubernetes v3.2.1.

### Known Gaps
- Contour 1.33.7 is tested against Kubernetes 1.34/1.33/1.32 only, so it now runs two minors past its tested matrix. Accepted deliberately: Contour has not cut a minor since 2025-09-09 and 1.34.0 has no release branch, so waiting had no end date, while holding at 1.34 would have cost roughly $365/month in extended support from 2026-12-02. Revisit when Contour 1.34 ships. Reasoning recorded in `docs/eks-upgrade.md`.
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

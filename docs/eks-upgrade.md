# EKS version upgrade runbook

EKS upgrades the control plane **one minor version at a time**. Going from 1.33 to 1.36
is three separate applies, not one. This branch therefore has one commit per hop, and you
apply and verify each hop before moving to the next commit.

## Why now

1.33 left standard support on 2026-07-29 and is billed at the extended-support rate.

| Version | EKS release | End of standard support | End of extended support |
| --- | --- | --- | --- |
| 1.33 | 2025-05-29 | 2026-07-29 | 2027-07-29 |
| 1.34 | 2025-10-02 | 2026-12-02 | 2027-12-02 |
| 1.35 | 2026-01-27 | 2027-03-27 | 2028-03-27 |
| 1.36 | 2026-06-02 | 2027-08-02 | 2028-08-02 |

Stopping at 1.34 puts the cluster back on extended-support billing in December 2026, which
is why the target is 1.36.

## Open risk: Contour

**No released Contour version is tested against Kubernetes 1.35 or 1.36.** Contour 1.33.7
(newest release as of 2026-09) supports 1.34/1.33/1.32. Support for 1.35/1.36 exists only
on Contour `main`; the 1.34.0 milestone is open with no release branch and no due date.

Contour is the ingress path for the entire platform, so decide before hop 2:

- **If Contour 1.34.0 has shipped** — re-vendor `terraform/manifests/contour.yaml` from
  `https://raw.githubusercontent.com/projectcontour/contour/<tag>/examples/render/contour.yaml`,
  confirm the tag against
  [the compatibility matrix](https://projectcontour.io/resources/compatibility-matrix/),
  and apply it before hop 2.
- **If it has not** — either hold at 1.34 and revisit, or accept running Contour outside
  its tested matrix. Contour uses only stable APIs (Ingress v1, its own HTTPProxy CRD,
  Gateway API), so it is likely to work, but it is untested by the project.

Check for a new release before starting:

```bash
curl -s https://api.github.com/repos/projectcontour/contour/releases/latest | jq -r .tag_name
```

## Commit order

| Commit | Apply target |
| --- | --- |
| `chore(deps): bump in-cluster components ahead of EKS upgrade` | still 1.33 — verify the new cluster-autoscaler, NTH and Contour on the current control plane |
| `feat(eks): upgrade control plane to Kubernetes 1.34` | hop 1 |
| `feat(eks): upgrade control plane to Kubernetes 1.35` | hop 2 — gated on Contour, see above |
| `feat(eks): upgrade control plane to Kubernetes 1.36` | hop 3 |

`terraform/autoscaler.tf` selects the cluster-autoscaler image tag from
`var.cluster_version`, so each hop pulls the matching CA release automatically. Adding a
future Kubernetes version means adding a row to `local.cluster_autoscaler_image_tags` — a
missing key fails at plan time rather than silently leaving CA behind.

## Per-hop procedure

Run from `terraform/` with credentials that can manage the cluster.

### 1. Pre-flight

Check EKS cluster insights for deprecated API usage. Insights look back over a rolling
30-day window and refresh every 24 hours, so do this well before you intend to apply:

```bash
aws eks list-insights --cluster-name teehr-hub --region us-east-2
aws eks describe-insight --cluster-name teehr-hub --region us-east-2 --id <insight-id>
```

Confirm the control plane and all nodes are on the same minor before starting a hop —
a node group left behind on a previous hop will block the next one:

```bash
kubectl version
kubectl get nodes -o wide
```

Confirm the private subnets have free IP addresses. EKS needs up to five for the new
control plane ENIs.

### 2. Apply

```bash
git checkout <hop commit>
terraform init -upgrade
terraform plan -var-file=teehr-hub.tfvars
terraform apply -var-file=teehr-hub.tfvars
```

The control plane update takes several minutes and cannot be paused or stopped. If EKS's
health checks fail it reverts on its own and the cluster stays on the prior version.

The `terraform-aws-modules/eks` module is pinned `~> 21.0`, so `init -upgrade` picks up the
newest 21.x. The EKS addons (coredns, kube-proxy, vpc-cni, ebs-csi, efs-csi) have no
version pinned, so they resolve to the default for the new cluster version as part of the
same apply.

### 3. Roll the node groups

Managed node groups are **not** upgraded with the control plane. The apply updates the
launch templates, but existing nodes keep their old kubelet until they are replaced. With
`min_size = 0` on every group except `core-a`, the scale-to-zero groups pick up the new AMI
on their next scale-up; `core-a` needs a deliberate roll.

Watch for node groups stuck on a stale version:

```bash
kubectl get nodes -o custom-columns=NAME:.metadata.name,VERSION:.status.nodeInfo.kubeletVersion,NG:.metadata.labels.teehr-hub/nodegroup-name
```

### 4. Verify before the next hop

- All nodes report the new kubelet version.
- `kubectl -n kube-system get pods` — coredns, kube-proxy, aws-node, CSI drivers, and
  cluster-autoscaler all healthy.
- `kubectl -n kube-system logs deploy/cluster-autoscaler --tail=50` — no API errors, and
  the image tag matches the new cluster minor.
- Ingress still serves: JupyterHub, the API, and the frontend all reachable.
- Trigger a scale-up on one notebook node group and one spot Spark node group to confirm
  autoscaling and the node-termination-handler still work on the new AMI.
- `terraform plan -var-file=teehr-hub.tfvars` reports no pending changes.

## Rollback

A hop can be rolled back to the previous minor within 7 days of completing, via
`aws eks update-cluster-version` or the console. Rolling back to a version in extended
support (1.33) requires the cluster upgrade policy to be `EXTENDED` first. After 7 days the
only path back is a new cluster.

Revert the corresponding commit so the tfvars match the live cluster version, otherwise the
next apply will push it forward again.

## Known upgrade notes per version

**1.34** — containerd 2.1. No AL2 optimized AMI is published; the node groups already use
`AL2023_x86_64_STANDARD`. AppArmor deprecated. VolumeAttributesClass graduates to GA.

**1.35** — cgroup v1 removed; the kubelet refuses to start on cgroup v1 nodes. AL2023
defaults to cgroup v2, so the node groups are unaffected. Last release supporting
containerd 1.x. IPVS kube-proxy mode deprecated.

**1.36** — `gitRepo` volumes permanently disabled. IPVS kube-proxy mode removed; the
cluster uses the default iptables mode. `StrictIPCIDRValidation` on by default, so IP and
CIDR values with leading zeros or non-canonical notation are rejected on create/update.
SELinux volume labeling changes go GA.

## Out of scope

cert-manager is pinned to chart v1.12.0 (May 2023), well behind the control plane. It is
being bumped separately because CRD conversion gives it a much larger blast radius than the
components in this branch.

`terraform/contour.tf` filters `CustomResourceDefinition` and `Job` objects out of the
`kubernetes_manifest` resources, so re-vendoring Contour does not update its CRDs or the
certgen Job. Those are managed out of band; see [migration-notes.md](migration-notes.md).

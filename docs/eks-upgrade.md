# EKS version upgrade runbook

EKS upgrades the control plane **one minor version at a time**. Going from 1.33 to 1.36
is three separate applies, not one.

There is no CI for this repo, so every apply is run by hand from a workstation. The branch
carries one commit per hop so the history records what was applied and when; the PR goes up
once all three hops are done and verified.

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

## Before you start

### Credentials

`eks:*` is denied without MFA by the `DEV-FORCE-MFA` policy, so start from an MFA session.
`kubectl` access additionally needs the `teehr-hub-teehr-hub-admin` role, which is the only
access entry on the cluster — `enable_cluster_creator_admin_permissions` is commented out in
`eks.tf`, so your own user has no cluster access of its own.

```bash
aws sts get-session-token --serial-number <mfa-arn> --token-code <code>
aws eks update-kubeconfig --name teehr-hub --region us-east-2 \
  --role-arn arn:aws:iam::<account>:role/teehr-hub-teehr-hub-admin
```

### Tooling

| Tool | Needs | Note |
| --- | --- | --- |
| aws-cli | 2.24+ | 2.18.15 lacks `eks describe-cluster-versions`; the insight commands below do work on it |
| terraform | 1.5+ | |
| kubectl | within one minor of the control plane | see below |
| helm | 3 or 4 | only needed for the cert-manager work, not for these hops |

**kubectl skew matters here.** Kubernetes supports kubectl within ±1 minor of the API
server. A 1.36 kubectl against the current 1.33 control plane is three minors ahead and
outside that window, so it can misreport or fail on some resources. Either keep a 1.34
kubectl for the early hops (`brew install kubernetes-cli@1.34`, or use `asdf`/`mise`) or
treat anything odd it reports before hop 3 with suspicion.

### State locking

The S3 backend in `versions.tf` sets no `dynamodb_table` and no `use_lockfile`, so **there
is no state locking**. Fine for a single operator, but make sure nobody else is applying
while you work through the hops.

### Pin the providers first

`terraform init -upgrade` would move the AWS provider 6.53 -> 6.66, the Helm provider
3.2 -> 3.3 and the EKS module 21.24 -> 21.26. Do that **once, up front, at 1.33**, verify a
clean plan, and commit the updated `.terraform.lock.hcl`. Then use plain `terraform init`
for the hops, so each hop's plan shows only the Kubernetes version change and not provider
churn mixed in with it.

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

### Decision, 2026-09-24: proceed to 1.36 anyway

Waiting was rejected because it has no end date. Contour's last minor, v1.33.0, shipped
2025-09-09 — twelve months with nothing since, against a historical cadence of two to four
months. The 1.34.0 milestone is open with no release branch. Meanwhile 1.34 leaves standard
support on 2026-12-02, and extended support costs $0.60 per cluster-hour against $0.10, so
holding would have cost roughly $365/month from December with no way to predict the wait.

The risk was judged acceptable because nothing Contour depends on changes in 1.35 or 1.36.
It uses Ingress v1, its own HTTPProxy CRDs, Gateway API, Leases and EndpointSlices, all
stable APIs. The breaking changes in those releases — cgroup v1 removal, IPVS removal,
gitRepo volumes, SELinux labeling — are node-level or kube-proxy-level and do not touch the
ingress control plane. Each hop also keeps a 7-day rollback window.

What that buys is untested, not unsupported-by-design. Verify ingress properly after hops 2
and 3 rather than relying on pods being `Running`, and revisit when Contour 1.34 ships.

## Working through the hops locally

Stay on the branch and walk `cluster_version` in `teehr-hub.tfvars` forward one minor at a
time, applying and verifying at each stop. The commits are already written in that order:

| Stage | `cluster_version` | What it covers |
| --- | --- | --- |
| provider/module pin | 1.33 | `init -upgrade`, clean plan, commit the lock file |
| `chore(deps)` | 1.33 | new cluster-autoscaler, NTH and Contour on the current control plane |
| `feat(eks): ... 1.34` | 1.34 | hop 1 |
| `feat(eks): ... 1.35` | 1.35 | hop 2 — gated on Contour, see above |
| `feat(eks): ... 1.36` | 1.36 | hop 3 |

To apply a stage, check out that commit (`git checkout <sha>`, detached) or reset the branch
to it, apply, verify, then move to the next. Applying `chore(deps)` on its own first is
deliberate: it proves the new cluster-autoscaler and Contour are healthy on 1.33 before the
control plane starts moving, so a later failure has one obvious cause instead of two.

If a hop needs a fix, commit it on the branch as you go. Open the PR once 1.36 is applied
and verified, so the PR describes what actually happened rather than what was planned.

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
terraform init
terraform plan -var-file=teehr-hub.tfvars -out=hop.tfplan
terraform apply hop.tfplan
```

Applying a saved plan rather than re-planning at apply time means what you reviewed is
exactly what runs — worth it here because there is no CI diffing it for you. `*.tfplan` is
gitignored.

The control plane update takes several minutes and cannot be paused or stopped. If EKS's
health checks fail it reverts on its own and the cluster stays on the prior version.

The EKS addons (coredns, kube-proxy, vpc-cni, ebs-csi, efs-csi) have no
version pinned, so they resolve to the default for the new cluster version as part of the
same apply.

### 3. Node groups

The apply rolls them for you. `main.tf` in the EKS module passes
`coalesce(var.kubernetes_version, aws_eks_cluster.this[0].version)` down to each node group,
which sets `version` on every `aws_eks_node_group`, so bumping `cluster_version` updates all
of them in the same apply. This is the slow part: the control plane takes about ten minutes,
then roughly twenty node groups update behind it.

Most are cheap. Every group except `core-a` sits at `desired_size = 0`, so there is nothing
to drain and the update returns almost immediately. `core-a` has a running node and is the
one that actually rolls — EKS surges a replacement (`max_size = 6` leaves room), drains the
old node, and respects PodDisruptionBudgets.

**`force_update_version` is not set**, so a PDB that cannot be satisfied will fail the node
group update rather than evict through it. `core-a` carries the core platform pods, and a
single-replica Deployment with `minAvailable: 1` will block its own eviction. If an update
hangs, that is the first thing to look at:

```bash
kubectl get pdb -A
kubectl -n <ns> describe pdb <name>     # ALLOWED DISRUPTIONS: 0 is the tell
```

Scale the offending Deployment to two replicas, or relax the PDB, and the drain proceeds.

Watch for node groups stuck on a stale version:

```bash
kubectl get nodes -o 'custom-columns=NAME:.metadata.name,VERSION:.status.nodeInfo.kubeletVersion,NG:.metadata.labels.teehr-hub/nodegroup-name'
```

### 4. Verify before the next hop

- All nodes report the new kubelet version.
- `kubectl -n kube-system get pods` — coredns, kube-proxy, aws-node, CSI drivers, and
  cluster-autoscaler all healthy.
- `kubectl -n kube-system logs deploy/cluster-autoscaler --tail=50` — no API errors, and
  the image tag matches the new cluster minor.
- Ingress still serves. From hop 2 onward Contour is outside its tested matrix, so check it
  properly rather than trusting pod status — a healthy Envoy that has stopped receiving
  xDS updates still looks `Running`:

  ```bash
  kubectl -n projectcontour logs deploy/contour --tail=100     # no xDS or watch errors
  kubectl get httpproxy -A                                     # every one still "valid"
  kubectl get ingress -A
  ```

  Then exercise each hostname end to end, not just the TLS handshake — a 200 from behind
  the proxy proves routing, not just that Envoy is listening:

  ```bash
  for h in hub api auth prefect minio xpublish-api; do
    printf '%-14s %s\n' "$h" "$(curl -s -o /dev/null -w '%{http_code}' "https://$h.<hostname>/")"
  done
  ```

  Changing an HTTPProxy and watching it take effect is the strongest signal that the xDS
  path is still live.
- Trigger a scale-up on one notebook node group and one spot Spark node group to confirm
  autoscaling and the node-termination-handler still work on the new AMI.
- `terraform plan -var-file=teehr-hub.tfvars` reports no pending changes.

## Known snag: DaemonSet annotation drift

Any apply that changes a DaemonSet pod template in `manifests/` fails like this:

```
Error: Provider produced inconsistent result after apply
  .object.metadata.annotations["deprecated.daemonset.template.generation"]:
  was cty.StringVal("1"), but now cty.StringVal("2")
```

The DaemonSet controller bumps that annotation whenever the pod template changes, and
`kubernetes_manifest` round-trip checks the entire object and rejects the response. It is an
open provider bug
([#2722](https://github.com/hashicorp/terraform-provider-kubernetes/issues/2722)); the fix
([#2941](https://github.com/hashicorp/terraform-provider-kubernetes/pull/2941)) postdates the
newest release, v3.2.1.

**The write succeeded.** "Inconsistent result *after* apply" means the API server accepted
the change and the provider disliked the response. Confirm in-cluster, then re-run the
apply. The second pass does not touch the pod template, so nothing bumps the annotation and
it converges:

```bash
kubectl -n kube-system get ds aws-node-termination-handler \
  -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
kubectl -n projectcontour get ds envoy \
  -o jsonpath='{.spec.template.spec.containers[*].image}{"\n"}'
```

Explicit `computed_fields` does not help, despite `metadata.annotations` being in its
default ([#1591](https://github.com/hashicorp/terraform-provider-kubernetes/issues/1591)).

This is the same root cause as the CRD and Job filtering in `contour.tf`. Deploying Contour
from its official Helm chart instead of vendored YAML would retire the whole class of
problem, but that is its own piece of work, not something to start mid-upgrade.

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

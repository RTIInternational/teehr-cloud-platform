# cert-manager v1.12.0 -> v1.21.2

cert-manager does not support jumping minor versions: upstream says to upgrade one minor at
a time, and v1.12 to v1.21 is nine of them. Their documented alternative for a gap this
large is a full uninstall and re-install, which is what this change does.

v1.21 is tested and supported on Kubernetes 1.33 through 1.36, so it is squarely inside its
supported matrix on this cluster — unlike Contour, which the EKS upgrade left running two
minors past its own. v1.12.0 is the outlier here, not the target.

That is safe here for one specific reason: **nothing about the certificate set is
imperative.** All six Certificates are rendered from
`teehr-cloud-core/cert-manager/manifests/cert.yaml.tpl` in the `teehr-hub` repo and the
`letsencrypt-prod` ClusterIssuer is in `terraform/manifests/cert-manager.yaml` here, so
every custom resource can be recreated from code.

## What survives and what does not

**The TLS Secrets survive.** Envoy serves TLS straight from
`hub.<hostname>-tls`, `api.<hostname>-tls` and so on, so ingress keeps serving with
cert-manager completely absent. Only renewal stops. This is why the maintenance window is
not user-facing.

Secrets survive only because `--enable-certificate-owner-ref` is off (the default, and the
current values file does not set it). With that flag on, deleting a Certificate cascades to
its Secret. **Verify this before you start** — see pre-flight below.

**The CRDs and every custom resource do not survive.** The v1.12 chart renders its CRDs
without `helm.sh/resource-policy: keep`, so `helm uninstall` deletes the CRDs, and deleting
a CRD deletes every Certificate, CertificateRequest, Order, Challenge and ClusterIssuer in
the cluster. This is expected and is why step 1 is a backup.

The v1.21.2 values set `crds.keep = true`, so a future uninstall will not do this again.

## Before you start

No CI applies this repo, so the whole procedure is run by hand. `eks:*` needs an MFA
session and `kubectl` needs the `teehr-hub-teehr-hub-admin` role; see
[eks-upgrade.md](eks-upgrade.md#credentials).

Step 1 uses the `helm` CLI directly. Helm 4 reads Helm 3 release records, so a Helm 4
client can uninstall this release even though the Terraform provider created it — but if
you have both on `PATH`, check which one you are about to run.

## Pre-flight

Confirm the certificate-owner-ref flag is not set. This must return nothing:

```bash
kubectl -n cert-manager get deploy cert-manager -o yaml | grep enable-certificate-owner-ref
```

If it *is* set, stop — removing cert-manager would take the TLS Secrets with it.

Back up everything:

```bash
kubectl get clusterissuers,issuers,certificates,certificaterequests -A -o yaml \
  > cert-manager-crs-backup.yaml
kubectl get secrets -A -l controller.cert-manager.io/fao=true -o yaml \
  > cert-manager-secrets-backup.yaml
```

Check no certificate is close to expiry. Renewal is paused for the length of the window, so
anything renewing in the next few days should be dealt with first:

```bash
kubectl get certificates -A -o custom-columns=\
NAME:.metadata.name,READY:.status.conditions[0].status,RENEWAL:.status.renewalTime,EXPIRY:.status.notAfter
```

Record the six Secret names so you can confirm afterwards that they were adopted rather
than reissued — compare `notAfter` before and after; an adopted certificate keeps its
original expiry.

## Procedure

Run from `terraform/`.

### 1. Uninstall the old release

```bash
helm uninstall cert-manager -n cert-manager
```

This deletes the CRDs and all cert-manager custom resources. The namespace is managed
outside this release (`create_namespace = false`) and stays.

### 2. Drop the stale resources from Terraform state

The release and the ClusterIssuer no longer exist, but Terraform still believes they do.
The ClusterIssuer matters most: `kubernetes_manifest` resolves its type against the API
server at **plan** time, so with the CRD gone, any plan that includes it fails outright.

```bash
terraform state rm helm_release.cert_manager
terraform state rm 'kubernetes_manifest.cert_manager["ClusterIssuer:cluster:letsencrypt-prod"]'
```

Confirm the exact state address first with `terraform state list | grep cert`.

### 3. Install v1.21.2

Targeted, so the plan graph excludes the ClusterIssuer whose CRD does not exist yet:

```bash
terraform apply -target=helm_release.cert_manager -var-file=teehr-hub.tfvars
```

Wait for all three deployments to be available before continuing — the webhook in
particular must be serving, or the ClusterIssuer in the next step is rejected:

```bash
kubectl -n cert-manager rollout status deploy/cert-manager
kubectl -n cert-manager rollout status deploy/cert-manager-webhook
kubectl -n cert-manager rollout status deploy/cert-manager-cainjector
```

### 4. Recreate the ClusterIssuer

```bash
terraform apply -var-file=teehr-hub.tfvars
kubectl get clusterissuer letsencrypt-prod -o wide
```

It must report `Ready=True` before the Certificates will resolve. The ACME account key is
in the `letsencrypt-prod` Secret in the cert-manager namespace; if that survived, the
existing ACME account is reused.

### 5. Recreate the Certificates

From the `teehr-hub` repo, against the remote environment:

```bash
garden deploy core-certs
```

### 6. Verify adoption, not reissue

```bash
kubectl get certificates -A -o custom-columns=\
NAME:.metadata.name,READY:.status.conditions[0].status,EXPIRY:.status.notAfter
```

All six should go `Ready=True` within a minute or so, with `notAfter` **unchanged** from the
pre-flight capture. An unchanged expiry means cert-manager adopted the existing Secret.

If expiries move, it reissued. That is not harmful in itself, but Let's Encrypt allows 5
duplicate certificates per week per identical name set, so a repeated failed run could hit
the rate limit. Stop and diagnose rather than retrying if more than one reissues
unexpectedly.

Then confirm each hostname still serves a valid chain:

```bash
for h in hub api auth prefect minio xpublish-api; do
  echo "== $h"
  echo | openssl s_client -connect "$h.<hostname>:443" -servername "$h.<hostname>" 2>/dev/null \
    | openssl x509 -noout -dates -issuer
done
```

## Rollback

Ingress keeps serving throughout, so rollback is rarely urgent. If v1.21.2 misbehaves,
repeat the procedure with the chart version pinned back to `v1.12.0` and restore the CRs
from `cert-manager-crs-backup.yaml`. The TLS Secrets were never touched.

## Related

Local development pins cert-manager separately, in
`teehr-cloud-core/cert-manager/garden.yaml`, still at `v1.12.0`. That needs a matching bump
in the `teehr-cloud-core` repo so local and remote do not drift.

The EKS 1.33 -> 1.36 upgrade is tracked separately in [eks-upgrade.md](eks-upgrade.md).
cert-manager v1.12 predates Kubernetes 1.28 and is far outside its tested range on 1.36,
which is why this is worth doing alongside it.

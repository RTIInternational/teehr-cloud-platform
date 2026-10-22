# Platform repository for TEEHR Cloud
This repository contains Terraform Infrastructure as Code (IaC) for AWS resources and the
in-cluster components that platform maintainers update over time.

## Terraform

Log in to AWS with credentials that have sufficient permissions.
We used Admin for testing but still need to determine the minimum set of permissions needed.
```bash
aws configure
```
Or set a profile
```bash
export AWS_PROFILE=ciroh_mdenno
```

There are two kinds of Terraform root, each with its own state in the `teehr-terraform-state` bucket (us-east-2):

- [terraform/global/](terraform/global/): account-wide resources shared by every cluster: admin and CI IAM, the
  Route 53 zone, and the CloudFront maintenance page. Nothing here depends on a cluster.
- [terraform/](terraform/): one regional stack (VPC, EKS, EFS, S3 warehouse buckets, IRSA roles, ECR, in-cluster
  platform components). Each stack has a backend file in [terraform/backends/](terraform/backends/) and a
  tfvars file; `teehr-hub.tfvars` with `backends/use2.hcl` is the us-east-2 stack.

### Day-to-Day Commands

Regional stack:

```bash
cd terraform
terraform init -reconfigure -backend-config=backends/use1.hcl
terraform plan -var-file=teehr-hub-use1.tfvars
terraform apply -var-file=teehr-hub-use1.tfvars
```

Global resources (see [docs/maintenance-page.md](docs/maintenance-page.md) before applying; a plain apply clears
any banner message):

```bash
cd terraform/global
terraform init
terraform plan -var-file=teehr-hub.tfvars
```

The EKS module tracks the latest node AMIs and add-on versions, so a regional apply usually also rolls every node
group to the latest AMI. That's routine but slow; use `-target` when you only want a quick, scoped change.

### Post-Apply Checklist

Review Terraform outputs:

```bash
terraform output
```

1. Verify target resources exist in AWS (EKS cluster, IAM roles, S3 bucket, and ECR repositories).
2. Record key output values needed by app deployment workflows. After creating or replacing a regional stack's
   load balancer, copy its `ingress_elb_hostname` output into `terraform/global/teehr-hub.tfvars`.
3. Re-run `terraform plan -var-file=teehr-hub.tfvars` and confirm it reports no pending changes.

### Building a new regional stack

Building a second stack next to an existing one (e.g. for the us-east-1 move) is a staged apply plus a few
in-cluster bootstrap steps; see [docs/new-regional-stack.md](docs/new-regional-stack.md).

### Region move

The us-east-2 to us-east-1 cutover runbook, with rollback, is [docs/region-move.md](docs/region-move.md).

### Upgrading the EKS version

EKS only moves one minor version at a time, and each hop needs its node groups rolled and
verified before the next one. The procedure, the current version support dates, and the
per-version breaking changes are in [docs/eks-upgrade.md](docs/eks-upgrade.md).

### Upgrading cert-manager

cert-manager cannot be upgraded across multiple minor versions in place. The uninstall and
re-install procedure, and the pre-flight checks that keep the TLS Secrets intact, are in
[docs/cert-manager-upgrade.md](docs/cert-manager-upgrade.md).

### Migration Notes

Historical migration details for cert-manager, Contour, and Cluster Autoscaler live in [docs/migration-notes.md](docs/migration-notes.md). Those import steps were only needed for the initial adoption of existing cluster resources, not for routine updates.

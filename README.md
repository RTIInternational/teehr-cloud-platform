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

State backend configuration is defined in [terraform/versions.tf](terraform/versions.tf) and currently points to the shared state bucket `teehr-terraform-state` in `us-east-2`.

### Day-to-Day Commands

```bash
cd terraform
terraform init
terraform plan -var-file=teehr-hub.tfvars
terraform apply -var-file=teehr-hub.tfvars
```

### Post-Apply Checklist

Review Terraform outputs:

```bash
terraform output
```

1. Verify target resources exist in AWS (EKS cluster, IAM roles, S3 bucket, and ECR repositories).
2. Record key output values needed by app deployment workflows.
3. Re-run `terraform plan -var-file=teehr-hub.tfvars` and confirm it reports no pending changes.

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

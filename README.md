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
  tfvars file: `teehr-hub-use1.tfvars` with `backends/use1.hcl` is the us-east-1 production stack, and
  `teehr-hub.tfvars` with `backends/use2.hcl` is the us-east-2 stack, kept until teardown.

### Day-to-Day Commands

Regional stack: for use1, prefer the GitHub Actions workflow (below). By hand, with AWS admin credentials:

```bash
cd terraform
terraform init -reconfigure -backend-config=backends/use1.hcl
terraform plan -var-file=teehr-hub-use1.tfvars
terraform apply -var-file=teehr-hub-use1.tfvars
```

For use2, use `backends/use2.hcl` and `teehr-hub.tfvars`.

Global resources (see [docs/maintenance-page.md](docs/maintenance-page.md) before applying; a plain apply clears
any banner message):

```bash
cd terraform/global
terraform init
terraform plan -var-file=teehr-hub.tfvars
```

The EKS module tracks the latest node AMIs and add-on versions, so a regional apply usually also rolls every node
group to the latest AMI. That's routine but slow; use `-target` when you only want a quick, scoped change.

### Applying with GitHub Actions

The **Terraform use1** workflow (`.github/workflows/terraform-use1.yml`) plans and applies the use1 stack without
personal AWS credentials. Run it from the Actions tab or `gh workflow run terraform-use1.yml --ref <branch>`:

1. It plans, and the plan appears in the run summary. Set `targets` (space-separated addresses) to limit it;
   a full plan usually rolls every node group to the latest AMI.
2. If there are changes, the apply job waits for a `production` reviewer. Approving applies exactly that plan;
   rejecting leaves a plan-only run.

Any branch can run it. After applying from a branch, merge it soon, or plans from `main` will show its changes
as reverts. `terraform/global/` and use2 are still applied by hand. Logs are public: sensitive values are redacted,
but don't add secrets as plain variables. CI pins Terraform 1.15.7 (`TF_VERSION`); keep local versions the same,
since a newer version writing state can stop older ones reading it.

One-time setup:
- An AWS admin applies `terraform/global/` (creates the plan and apply roles), then the two access entries on use1:

  ```bash
  terraform apply -var-file=teehr-hub-use1.tfvars \
    -target='module.eks.aws_eks_access_entry.this["github_terraform_plan"]' \
    -target='module.eks.aws_eks_access_entry.this["github_terraform_apply"]' \
    -target='module.eks.aws_eks_access_policy_association.this["github_terraform_plan_admin_view_policy"]' \
    -target='module.eks.aws_eks_access_policy_association.this["github_terraform_apply_admin_policy"]'
  ```
- A repo admin creates the GitHub environments `terraform-plan` (no reviewers) and `production` (required
  reviewers), and protects `main` (PR with one approval, no force pushes). Do this before the first run: GitHub
  creates a missing environment with no reviewers, so an apply wouldn't wait for approval.

Apply `global/` before the next regional plan, manual or workflow: `eks.tf` looks up the CI roles by name. If an
apply fails, re-run the whole workflow, not just the apply job: the saved plan is deleted after each apply attempt.

### Post-Apply Checklist

Review Terraform outputs:

```bash
terraform output
```

1. Verify target resources exist in AWS (EKS cluster, IAM roles, S3 bucket, and ECR repositories).
2. Record key output values needed by app deployment workflows. After creating or replacing a regional stack's
   load balancer, copy its `ingress_elb_hostname` output into `terraform/global/teehr-hub.tfvars`.
3. Re-run the plan (`terraform plan -var-file=teehr-hub-use1.tfvars`, or the workflow with no `targets`) and
   confirm it reports no pending changes.

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

# Building a new regional stack

How to build a second copy of the regional root (`terraform/`) next to an existing one, e.g. the us-east-1
stack for the region move (RTIInternational/teehr-hub#462). Shared resources (DNS, CloudFront, admin/CI IAM)
live in `terraform/global/` and aren't created again.

A stack is a backend file in `terraform/backends/` plus a tfvars file. The us-east-1 stack is
`backends/use1.hcl` + `teehr-hub-use1.tfvars`. What makes it safe to build next to us-east-2:

- `cluster_name` differs (`teehr-hub-use1`), so every IAM name built from it is new. `legacy_iam_names` stays
  off.
- The warehouse bucket names are new; S3 names are global.
- `cluster_creator_admin = true` gives the identity running Terraform an EKS access entry, which the
  kubernetes/helm providers need on the new cluster.
- `azs` puts node groups and the EFS mount target in an AZ with all the node instance types. Check spot
  capacity with `aws ec2 get-spot-placement-scores` when choosing.

## 1. AWS resources

The kubernetes/helm resources can't plan until the cluster exists, so the first apply targets everything
else. Expect about 20 minutes for the cluster and node groups. `ciroh_mdenno` is the profile for the teehr-hub
account (935462133478). The code blocks have no comments, so they paste cleanly into zsh.

```bash
export AWS_PROFILE=ciroh_mdenno
cd terraform
terraform init -reconfigure -backend-config=backends/use1.hcl

T=(
  -target=module.vpc -target=module.eks -target=aws_vpc_endpoint.s3
  -target=aws_efs_mount_target.datadir -target=aws_ecr_lifecycle_policy.repos
  -target=aws_s3_bucket_public_access_block.teehr_iceberg_warehouse_public_access_block
  -target=aws_s3_bucket_public_access_block.teehr_icechunk_warehouse_public_access_block
  -target=aws_iam_role_policy_attachment.cluster_autoscaler
  -target=aws_iam_role_policy_attachment.ebs_csi_driver
  -target=aws_iam_role_policy_attachment.efs_csi_driver
  -target=aws_iam_role_policy_attachment.iceberg_s3_warehouse_readonly
  -target=aws_iam_role_policy_attachment.iceberg_s3_warehouse_rw
  -target=aws_iam_role_policy_attachment.polaris_assume_warehouse_role
  -target=aws_iam_role_policy_attachment.prefect_job_iceberg_rw
  -target=aws_iam_role_policy_attachment.prefect_job_icechunk_rw
  -target=aws_iam_role_policy_attachment.icechunk_s3_warehouse_readonly
  -target=aws_iam_role_policy_attachment.vpc_cni_policy
  -target=aws_iam_role_policy_attachment.xpublish_api_assume_icechunk_role
  -target=aws_iam_role_policy_attachment.xpublish_api_icechunk_readonly
)
terraform apply -var-file=teehr-hub-use1.tfvars "${T[@]}"
```

## 2. In-cluster components

In order:

1. `bootstrap-cluster-extras.sh pre` creates the cert-manager namespace and the Contour CRDs, which Terraform
   doesn't own.
2. A targeted apply installs cert-manager. The ClusterIssuer in `manifests/cert-manager.yaml` can't plan until
   the chart has installed cert-manager's CRDs.
3. A full apply creates the rest: ClusterIssuer, Contour, cluster-autoscaler, node termination handler.
4. `bootstrap-cluster-extras.sh post` runs the Contour certgen Job, which needs the namespace and RBAC from step 3.

```bash
aws eks update-kubeconfig --name teehr-hub-use1 --region us-east-1
CONTEXT=arn:aws:eks:us-east-1:935462133478:cluster/teehr-hub-use1
CONTEXT=$CONTEXT ../scripts/bootstrap-cluster-extras.sh pre
terraform apply -var-file=teehr-hub-use1.tfvars -target=helm_release.cert_manager
terraform apply -var-file=teehr-hub-use1.tfvars
CONTEXT=$CONTEXT ../scripts/bootstrap-cluster-extras.sh post
```

The Envoy Service creates its load balancer during this apply. If `terraform output ingress_elb_hostname` is
null, wait a minute and run `terraform apply -refresh-only -var-file=teehr-hub-use1.tfvars`.

Check:

```bash
kubectl --context $CONTEXT get nodes
kubectl --context $CONTEXT -n projectcontour get pods,svc
kubectl --context $CONTEXT get clusterissuer letsencrypt-prod
```

## 3. Staging DNS

Point `*.use1.teehr.rtiamanzi.org` at the new load balancer so the stack can be tested before cutover. In
`terraform/global/teehr-hub.tfvars`:

```hcl
staging_ingress = {
  use1 = {
    elb_hostname = "<ingress_elb_hostname output from step 2>"
    elb_region   = "us-east-1"
  }
}
```

Then apply in `terraform/global`, passing the current banner message (see
[maintenance-page.md](maintenance-page.md)).

## 4. Hand-off to the app deploy

App deployments need the new stack's values (`terraform output`): `cluster_arn`, `ecr_registry`,
`nfs_server_dns`, the IRSA role ARNs, and the bucket names. They go in the deployment repo's deploy target for
this stack.

Before the first app deploy, the deployment repo has to create the `ecr-config` secret in the `default`
namespace. Garden checks it on every deploy and fails with `Could not find secret 'ecr-config'` without it.
Add the new `ecr_registry` to the deployment repo's `config.json` first. From the teehr-hub repo root:

```bash
CONTEXT=arn:aws:eks:us-east-1:935462133478:cluster/teehr-hub-use1 ./create-ecr-secret-helper.sh
```

region = "us-east-1"

cluster_name = "teehr-hub-use1"

cluster_version = "1.36"

environment = "dev"

project_name = "teehr"

# us-east-1c (use1-az2) first: node groups and the EFS mount target go there.
# It had the best spot placement score for r5/r5a/r5n.4xlarge (2026-10-14).
# Avoid us-east-1e, which lacks these instance types.
azs = ["us-east-1c", "us-east-1d", "us-east-1b"]

# Lets Terraform's kubernetes/helm providers reach the new cluster.
cluster_creator_admin = true

# No default StorageClass on clusters created on 1.30+.
create_default_storage_class = true

# Built and pushed by RTIInternational/hefs-fews-hub. us-east-2 has a
# hand-made repo with this name, so it's only managed here.
additional_ecr_repos = [
  { name = "hefs-fews-hub", max_image_count = 10 },
]

iceberg_warehouse_bucket  = "teehr-iceberg-warehouse-use1"
icechunk_warehouse_bucket = "teehr-icechunk-warehouse-use1"

# CIROH project IDs for dedicated node groups
# Each project ID will create: nb-r5-xlarge-{id}, nb-r5-4xlarge-{id}, spark-r5-4xlarge-spot-{id}
project_ids = ["MMM", "Testbed", "FIRO", "ResOps", "FFF"]

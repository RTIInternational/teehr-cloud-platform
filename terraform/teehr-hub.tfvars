region = "us-east-2"

cluster_name = "teehr-hub"

cluster_version = "1.36"

environment = "dev"

project_name = "teehr"

iceberg_warehouse_bucket  = "dev-teehr-iceberg-warehouse"
icechunk_warehouse_bucket = "dev-teehr-icechunk-warehouse"

# IAM names predate the per-cluster prefixes; drop with this stack.
legacy_iam_names = true

# Created by hand with AES256 encryption; importing it would replace the repo
# (and delete its images) to switch to KMS. Drop with this stack.
unmanaged_ecr_repos = ["teehr-hub/xpublish-api"]

# CIROH project IDs for dedicated node groups
# Each project ID will create: nb-r5-xlarge-{id}, nb-r5-4xlarge-{id}, spark-r5-4xlarge-spot-{id}
# Example: project_ids = ["MMM", "ABC", "XYZ"]
project_ids = ["MMM", "Testbed", "FIRO", "ResOps", "FFF"]
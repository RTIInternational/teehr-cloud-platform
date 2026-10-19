region = "us-east-2"

cluster_name = "teehr-hub"

cluster_version = "1.36"

environment = "dev"

project_name = "teehr"

iceberg_warehouse_bucket  = "dev-teehr-iceberg-warehouse"
icechunk_warehouse_bucket = "dev-teehr-icechunk-warehouse"

# IAM names predate the per-cluster prefixes; drop with this stack.
legacy_iam_names = true

# Replicate /data to the us-east-1 stack until cutover; removing this deletes
# the replication and makes the destination writable.
efs_replication_destination = {
  file_system_id = "fs-088cf95ec74bdfc16"
  region         = "us-east-1"
}

# CIROH project IDs for dedicated node groups
# Each project ID will create: nb-r5-xlarge-{id}, nb-r5-4xlarge-{id}, spark-r5-4xlarge-spot-{id}
# Example: project_ids = ["MMM", "ABC", "XYZ"]
project_ids = ["MMM", "Testbed", "FIRO", "ResOps", "FFF"]
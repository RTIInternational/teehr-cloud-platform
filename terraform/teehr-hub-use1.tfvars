region = "us-east-1"

cluster_name = "teehr-hub-use1"

cluster_version = "1.36"

environment = "dev"

project_name = "teehr"

# us-east-1c (use1-az2) first: node groups and the EFS mount target go there.
# It had the best spot placement score for r5/r5a/r5n.4xlarge (2026-10-14).
# Avoid us-east-1e, which lacks these instance types.
azs = ["us-east-1c", "us-east-1d", "us-east-1b"]

# Only while building the cluster. Off now that the admin and CI roles have
# their own access entries.
cluster_creator_admin = false

# No default StorageClass on clusters created on 1.30+.
create_default_storage_class = true

# Built and pushed by RTIInternational/hefs-fews-hub.
additional_ecr_repos = [
  { name = "hefs-fews-hub", max_image_count = 10 },
]

# Send traffic to IPv6 destinations through an egress-only internet gateway
# instead of the NAT gateway (teehr-cloud-platform #36).
enable_ipv6_egress = true

iceberg_warehouse_bucket  = "teehr-iceberg-warehouse-use1"
icechunk_warehouse_bucket = "teehr-icechunk-warehouse-use1"
db_backup_bucket          = "teehr-db-backups-use1"
upload_staging_bucket     = "teehr-upload-staging-use1"
upload_cors_origins       = ["https://dashboards.teehr.rtiamanzi.org", "https://control-plane.teehr.rtiamanzi.org"]

# HEFS-FEWS data (teehr-hub#525).
hefs_data_bucket = "ciroh-rti-hefs-data-use1"

# CIROH project IDs for dedicated node groups
# Each project ID will create: nb-r5-xlarge-{id}, nb-r5-4xlarge-{id}, spark-r5-4xlarge-spot-{id}
project_ids = ["MMM", "Testbed", "FIRO", "ResOps", "FFF"]

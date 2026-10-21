# Region move cutover: us-east-2 to us-east-1

Runbook for moving teehr-hub from the `teehr-hub` cluster (us-east-2) to `teehr-hub-use1` (us-east-1) on
2026-10-21 (RTIInternational/teehr-hub#462, #19). The us-east-1 stack is already built and running on the
`*.use1.teehr.rtiamanzi.org` staging hosts with its Prefect schedules paused, `/data` is replicating from
us-east-2, and the warehouse buckets have had a bulk copy.

Code blocks have no comments so they paste cleanly into zsh. Run them from the repo named at the start of each
step, **on `main`**: older branches lack fixes to these scripts. All AWS commands assume
`export AWS_PROFILE=ciroh_mdenno`.

The notes marked **2026-10-21** are problems hit during the actual cutover, with what fixed them.

```bash
export AWS_PROFILE=ciroh_mdenno
USE2=arn:aws:eks:us-east-2:935462133478:cluster/teehr-hub
USE1=arn:aws:eks:us-east-1:935462133478:cluster/teehr-hub-use1
```

## The day before

1. Re-run the bucket sync, so the cutover sync only has a day's writes to copy (teehr-hub):

   ```bash
   cd warehouse/remote/05_region_move
   ./01_sync_buckets.sh
   ```

2. Dry-run the table migration on one table (`02` with `ONLY_TABLES = ["teehr.units"]`, `03`, then `04` with
   `DRY_RUN = True`, which drops the table again at the end). Every check in `04` must pass.
3. Dry-run the Keycloak copy (teehr-cloud-core). It changes nothing; check the counts and dump sizes look sane:

   ```bash
   SRC_CONTEXT=$USE2 DST_CONTEXT=$USE1 DRY_RUN=1 ./scripts/copy-keycloak-db.sh
   ```

4. Open, but don't merge, the teehr-hub PR for step 9: in `deploy-targets/use1.yml`, set
   `hostname: teehr.rtiamanzi.org` and remove the `prefect:` block.
5. Have a user in **use1's** Keycloak (`auth.use1.teehr.rtiamanzi.org`) in the catalog-admin group, for step 6.

## Cutover

### 1. Maintenance on (teehr-cloud-platform, `terraform/global`)

App hosts start serving the maintenance page within a minute (60s TTL). The `*.use1` staging hosts aren't
affected.

```bash
cd terraform/global
terraform apply -var-file=teehr-hub.tfvars -var maintenance_mode=true -var 'maintenance_message=TEEHR Hub is moving to a new AWS region today. Back later today.'
```

To keep using the us-east-2 JupyterHub (step 4), point its hostnames at the us-east-2 load balancer in
`/etc/hosts`, using one of the IPs from the `dig` below:

```bash
dig +short af55ad7d6786c4889a7dea3336d2f79e-2141472567.us-east-2.elb.amazonaws.com
```

```
<ip>  hub.teehr.rtiamanzi.org auth.teehr.rtiamanzi.org
```

Then fully quit and reopen the browser. **2026-10-21:** a browser that was already open kept using its
connection to the maintenance page (CloudFront advertises HTTP/3, and the wildcard certificate lets it reuse the
connection for every `*.teehr` host) and ignored `/etc/hosts`. Classic ELB IPs also change; re-run the `dig` if
use2 stops answering.

### 2. Stop writes on us-east-2 (teehr-hub)

Pause every Prefect deployment (this also deletes queued runs), then wait in the Prefect UI until no flow run
is Running or Pending. Cancel any you don't want to wait for; the ingest lookbacks cover the gap.

```bash
kubectl --context $USE2 -n teehr-hub exec -i deploy/prefect-worker -- python - < prefect-workflows/pause_deployments.py
```

### 3. Final bucket sync (teehr-hub)

**2026-10-21:** `01` excluded the test tables by folder name, but the live table
`teehr.nwmd_metrics_by_location_v2` is stored in the `nwmd_metrics_by_location_v2_test` folder (an Iceberg
rename doesn't move files), so its data wasn't copied and `03` failed for it. Fixed by syncing that folder's
data (excluding `metadata/` and `_region_move/`) and re-running `03`. Check table locations, not names, before
excluding anything.

```bash
cd warehouse/remote/05_region_move
./01_sync_buckets.sh
```

### 4. Rewrite table paths (us-east-2 JupyterHub)

Run `warehouse/remote/05_region_move/02_rewrite_table_paths.ipynb` with `ONLY_TABLES = None`. Note the run ID
it prints. In a terminal there, copy the manifest to your home folder and download it:

```bash
cp /data/region_move/<run id>/rewrite_manifest.json ~/
```

### 5. Copy staged metadata (teehr-hub, laptop)

Must end with "All tables ready to register", with every table reporting "metadata points at
s3://teehr-iceberg-warehouse-use1/...". From here on, **don't run `01_sync_buckets.sh` again**: the rewritten
metadata keeps the original file names, so a sync would copy the old-path originals back over it.

```bash
cd warehouse/remote/05_region_move
./03_copy_staged_metadata.sh rewrite_manifest.json
```

### 6. Register tables (use1 JupyterHub, `hub.use1.teehr.rtiamanzi.org`)

Wait until the manifest has replicated (`ls /data/region_move/` on use1 shows the run ID; usually within 15
minutes). Run `04_register_tables.ipynb` with `RUN_ID` set and `DRY_RUN = False`. It must end with "All
tables match."

**2026-10-21:** `rewrite_table_path` (Iceberg 1.10.1) rewrites the manifests but writes the manifest lists with
each manifest's *original* length. Spark tolerates that, so `04` passed, but Trino reads by the recorded length
and failed with `Not an Avro data file` on most tables. Fix, in a use1 notebook, after registering:

1. `CALL iceberg.system.rewrite_manifests(table => '<table>')` for every table.
2. It skips a table with a single manifest, so for those set `commit.manifest.target-size-bytes` to `1024`,
   rewrite (splits it), restore the property, and rewrite again (merges).
3. Check through **Trino**, not just Spark: `SELECT count(*)` on every table must succeed.

### 7. Copy Keycloak and API databases (teehr-cloud-core)

Stops Keycloak and the API on both clusters, copies the databases, compares counts, and starts the use1 side
again. us-east-2 stays stopped. After this, use1's logins are the us-east-2 users.

The script's `api_keys` count shows `n/a`: the API keys are in the `keycloak` database, not `teehr_api`
(teehr-cloud-core#102). They're copied with it; compare `select count(*) from api_keys` in `keycloak` on both
sides by hand.

```bash
SRC_CONTEXT=$USE2 DST_CONTEXT=$USE1 DRY_RUN=1 ./scripts/copy-keycloak-db.sh
SRC_CONTEXT=$USE2 DST_CONTEXT=$USE1 ./scripts/copy-keycloak-db.sh
```

### 8. EFS failover (teehr-cloud-platform, `terraform/`)

Confirm the last replication is after writes stopped, i.e. after step 2:

```bash
aws efs describe-replication-configurations --region us-east-2 --file-system-id fs-0cb715f5b7a76e862 --query "Replications[0].Destinations[0].[Status,LastReplicatedTimestamp]" --output text
```

Then delete the replication: remove `efs_replication_destination` from `teehr-hub.tfvars` and apply the
us-east-2 stack. use1's `/data` becomes writable.

```bash
terraform init -reconfigure -backend-config=backends/use2.hcl
terraform apply -var-file=teehr-hub.tfvars -target=aws_efs_replication_configuration.datadir
```

Then remove `efs_replication_overwrite` from `teehr-hub-use1.tfvars` and apply the use1 stack:

```bash
terraform init -reconfigure -backend-config=backends/use1.hcl
terraform apply -var-file=teehr-hub-use1.tfvars -target=aws_efs_file_system.datadir
```

Commit both tfvars changes.

### 9. Deploy use1 as production (teehr-hub)

Merge the PR from "The day before" step 4, then run **Garden Deploy Remote** from `main` with target `use1`.
This switches use1 to the `teehr.rtiamanzi.org` hostnames (Keycloak's bootstrap updates the client redirect
URIs) and resumes its Prefect schedules.

**2026-10-21:** Garden's action versions ignore variables used inside manifest templates, so most
hostname-dependent deploys were skipped as "Already deployed". `force` (teehr-hub#477) fixed the ingresses and
certificates, but not `keycloak` or `keycloak-realm-config`, which were only pulled in as dependencies. What
worked:

1. Run the deploy with **force** checked.
2. Patch Keycloak's hostname and delete the two stale config maps, then deploy again:

   ```bash
   kubectl --context $USE1 -n teehr-hub patch keycloak keycloak --type merge -p '{"spec":{"hostname":{"hostname":"https://auth.teehr.rtiamanzi.org"}}}'
   kubectl --context $USE1 -n teehr-hub delete configmap keycloak-realm-bootstrap xpublish-api-config
   ```

3. Restart the pods that read hostname-based config at startup (CORS failures on the dashboards otherwise):

   ```bash
   kubectl --context $USE1 -n teehr-hub rollout restart deploy/teehr-api deploy/xpublish-api
   ```

4. Confirm nothing still names the staging hosts: no ConfigMap, Deployment, StatefulSet, HTTPProxy or Keycloak
   resource should contain `use1.teehr.rtiamanzi.org`.

### 10. DNS to use1, maintenance off (teehr-cloud-platform, `terraform/global`)

Get use1's load balancer:

```bash
cd terraform
terraform init -reconfigure -backend-config=backends/use1.hcl
terraform output ingress_elb_hostname
```

In `terraform/global/teehr-hub.tfvars`, set `ingress_elb_hostname` to that value and `ingress_elb_region =
"us-east-1"`. Then apply without the maintenance vars, which turns maintenance off and clears the banner:

```bash
cd global
terraform apply -var-file=teehr-hub.tfvars
```

Remove the `/etc/hosts` lines from step 1. Commit the tfvars change.

### 11. Certificates and smoke tests

cert-manager can only issue the production certificates once DNS points at use1, so expect TLS errors for a few
minutes. Wait for every certificate to be Ready:

```bash
kubectl --context $USE1 -n teehr-hub get certificate
```

Then check:

- `https://dashboards.teehr.rtiamanzi.org` loads, and forecast/retrospective dashboards show data.
- Log in to `https://hub.teehr.rtiamanzi.org` as an existing user, start a server, write a file under `/data`,
  and read a table from a notebook.
- An existing API key works against `https://api.teehr.rtiamanzi.org`.
- Prefect UI shows the deployments active; watch the first scheduled ingests succeed.

## Rollback

**Before step 7** (Keycloak copy): nothing on us-east-2 has been stopped except Prefect. Resume it, turn
maintenance off (step 10's apply, with DNS still on us-east-2), and remove the `/etc/hosts` lines:

```bash
kubectl --context $USE2 -n teehr-hub exec -i deploy/prefect-worker -- python - --resume < prefect-workflows/pause_deployments.py
```

**After step 7:** also restart Keycloak and the API on us-east-2 (the copy script prints these commands):

```bash
kubectl --context $USE2 -n teehr-hub patch keycloak keycloak --type merge -p '{"spec":{"instances":1}}'
kubectl --context $USE2 -n teehr-hub scale deploy teehr-api --replicas=1
```

**After step 10:** point `ingress_elb_hostname`/`ingress_elb_region` back at the us-east-2 load balancer and
apply `terraform/global`, then do the above. Anything written on use1 in between (ingests, `/data`, new users)
isn't on us-east-2.

us-east-2 stays up, untouched, until teardown (#20), so rollback stays possible through the soak period.

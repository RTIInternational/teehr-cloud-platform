# HEFS bucket move: us-east-2 to us-east-1

Runbook for copying the public HEFS-FEWS data bucket `ciroh-rti-hefs-data` (us-east-2, hand-made) to
`ciroh-rti-hefs-data-use1` (us-east-1, `terraform/s3.tf`) and switching its users over
(RTIInternational/teehr-hub#525). The cluster moved on 2026-10-21 (see [region-move.md](region-move.md)), so every
HEFS read from it now crosses regions.

**`GEFSv12/` isn't copied.** It's 8.8 TB of the 9.08 TB, hasn't been written since 2025-07, and isn't needed. It's
deleted with the old bucket in step 7.

The copy runs from a laptop with `aws s3 sync`, as the warehouse buckets did for the region move. Code blocks have
no comments so they paste cleanly into zsh. Set `AWS_PROFILE` to your own profile for account 935462133478 first.

## What's in the bucket (2026-11-16)

| | |
|---|---|
| Size | 9.08 TB, 921,519 objects, none over 5 GB |
| Copied | Everything except `GEFSv12/`: 278 GB, 671,092 objects (927 over 8 MB, largest 4.5 GB) |
| Not copied | `GEFSv12/`: 8.8 TB, 250k objects, last written 2025-07-22 |
| Last write | 2026-10-30 (`HEFS_FEWS/WGRFC`, `ohdPlugins/` in four RFCs, `FIRO/`) |
| Writers | People with their own IAM credentials, by hand. No workflow or cluster role writes to it. |
| Readers | Public `GetObject`. hefs-fews-hub downloads `HEFS_FEWS/<RFC>`. The Jupyter IRSA role can list. |
| Settings | Public-read bucket policy, ACLs blocked, `BucketOwnerEnforced`, SSE-S3, no versioning, no lifecycle, no object tags |

The new bucket has the same settings, plus a rule that aborts incomplete multipart uploads after 7 days.

**Why a laptop is enough:** the copy is server-side (`CopyObject`, plus `UploadPartCopy` for objects over 8 MB), so
the data never passes through the machine running it. That machine only sends about 671k small requests, so the
time depends on how many run at once, not on bandwidth. Expect roughly 1–2 hours at 64 concurrent requests. The
sync is incremental, so if the laptop sleeps or the network drops, run it again and it picks up where it stopped.

**Cost, at list prices:** about $3 inter-region transfer ($0.01/GB, Ohio to N. Virginia) and about $3.50 in copy
requests. The new bucket costs about $6.40/month to store. Deleting the old bucket in step 7 saves about $209/month.

**Who runs what:**

| Step | Needs |
|---|---|
| 1 | Write access to this repo, and a `production` reviewer to approve the workflow |
| 2–4, 5.1–5.3, 5.6 | The operator's own IAM user, in `teehr-hub-use1-hefs-data-s3-writers` (step 2). It can already read the old bucket. |
| 2, 5.4 | An admin (`iam:AddUserToGroup`) |
| 5.5, 7 | An admin: put, delete and remove the old bucket's policy, delete its objects, delete the bucket |

```bash
SRC=ciroh-rti-hefs-data
DST=ciroh-rti-hefs-data-use1
```

## 1. Create the bucket (Terraform)

Run the `terraform-use1` workflow (Actions, Run workflow) on `main` after the PR merges, leaving `targets` empty.
The plan should add the bucket and its settings, the `teehr-hub-use1-hefs-data-s3-write` policy and
`teehr-hub-use1-hefs-data-s3-writers` group, and update `teehr-hub-use1-iceberg-s3-warehouse-readonly` in place to
add the new bucket. It should change nothing else.

Check:

```bash
aws s3api get-bucket-location --bucket $DST
aws s3api get-bucket-policy --bucket $DST --query Policy --output text
aws s3api get-public-access-block --bucket $DST
```

## 2. Give the operator write access

An admin adds the operator's IAM user to the writers group. The group's policy covers what `sync` needs on the new
bucket, `--delete` included.

```bash
aws iam add-user-to-group --group-name teehr-hub-use1-hefs-data-s3-writers --user-name <operator>
```

If the operator isn't one of the regular writers, remove them again after step 5
(`aws iam remove-user-from-group`).

## 3. Bulk copy

Raise the CLI's concurrency for your profile. The default is 10, which makes the copy several times slower:

```bash
aws configure set s3.max_concurrent_requests 64 --profile "$AWS_PROFILE"
aws configure set s3.max_queue_size 10000 --profile "$AWS_PROFILE"
```

Keep the machine awake for the whole run (on WSL, Windows sleep stops it too), and run it inside `tmux` if you have
it:

```bash
time aws s3 sync s3://$SRC s3://$DST --source-region us-east-2 --region us-east-1 --exclude "GEFSv12/*" --only-show-errors 2>&1 | tee -a hefs-sync-$(date -u +%Y%m%dT%H%M%SZ).log
```

**Every sync and listing of the source in this runbook excludes `GEFSv12/`.** A sync without `--exclude` would
start copying 8.8 TB.

If it stops, run the same command again: objects that already match by size and timestamp are skipped. To check
progress from another terminal, run `aws s3 ls s3://$DST --recursive --summarize | tail -2`. Afterwards, put the
concurrency back with `aws configure set s3.max_concurrent_requests 10 --profile "$AWS_PROFILE"`.

## 4. Verify

Compare keys and sizes. ETags can differ for multipart copies, so they aren't compared.

```bash
aws s3api list-objects-v2 --bucket $SRC --region us-east-2 --query 'Contents[].[Key,Size]' --output text | grep -v '^GEFSv12/' | sort > hefs-src.tsv
aws s3api list-objects-v2 --bucket $DST --region us-east-1 --query 'Contents[].[Key,Size]' --output text | sort > hefs-dst.tsv
wc -l hefs-src.tsv hefs-dst.tsv
diff hefs-src.tsv hefs-dst.tsv | head -50
```

Both files should have the same line count (671,092 as of 2026-11-16, plus anything written since), and `diff`
should print nothing.

Anyone can read objects, but listing needs credentials:

```bash
KEY=$(aws s3api list-objects-v2 --bucket $DST --prefix HEFS_FEWS/ --max-items 1 --query 'Contents[0].Key' --output text)
curl -s -o /dev/null -w '%{http_code}\n' "https://$DST.s3.us-east-1.amazonaws.com/$KEY"
curl -s -o /dev/null -w '%{http_code}\n' "https://$DST.s3.us-east-1.amazonaws.com/?list-type=2"
```

The first should print 200 and the second 403.

## 5. Cutover

1. **Freeze writes** to `ciroh-rti-hefs-data`: tell everyone who writes to it, then wait for confirmation.
2. **Final sync.** Do a dry run first, so the deletes (objects removed from the source since the bulk copy) can be
   reviewed. `--exclude` also keeps `--delete` from touching anything under `GEFSv12/`.

   ```bash
   aws s3 sync s3://$SRC s3://$DST --source-region us-east-2 --region us-east-1 --exclude "GEFSv12/*" --delete --dryrun | tee hefs-final-dryrun.log | grep -c delete
   aws s3 sync s3://$SRC s3://$DST --source-region us-east-2 --region us-east-1 --exclude "GEFSv12/*" --delete --only-show-errors 2>&1 | tee -a hefs-final-sync.log
   ```

   Then repeat step 4.
3. **Switch readers.** In RTIInternational/hefs-fews-hub, change `BUCKET_NAME` in
   `src/hefs_fews_hub/dashboard_funcs.py` and `panel_dashboard.py` to `ciroh-rti-hefs-data-use1`, and
   `AWS_DEFAULT_REGION` in `entrypoint.sh`, `.env.example` and `docs/AWS_SETUP.md` to `us-east-1`. Update the bucket
   name in `docs/notes.md`. Images only publish on a `v*.*.*` tag, so the PR can merge early. Release by tagging
   it, then point the HEFS profile choices in teehr-hub (generated by
   `teehr-cloud-core/jupyterhub-profiles/generate_profile_list.py`) at the new tag. Also update the `wget` URL in
   RTIInternational/teehr `playground/metrics/calculate_reference_forecast.ipynb`.
4. **Switch writers.** An admin adds each writer's IAM user to the group:

   ```bash
   aws iam add-user-to-group --group-name teehr-hub-use1-hefs-data-s3-writers --user-name <user>
   ```

5. **Make the old bucket read-only**, so a stale script can't write to it. This replaces its policy, keeping the
   public read:

   ```bash
   aws s3api put-bucket-policy --bucket $SRC --region us-east-2 --policy "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Sid\":\"PublicRead\",\"Effect\":\"Allow\",\"Principal\":\"*\",\"Action\":\"s3:GetObject\",\"Resource\":\"arn:aws:s3:::$SRC/*\"},{\"Sid\":\"MovedToUse1\",\"Effect\":\"Deny\",\"Principal\":\"*\",\"Action\":[\"s3:PutObject\",\"s3:DeleteObject\"],\"Resource\":\"arn:aws:s3:::$SRC/*\"}]}"
   ```

6. **Unfreeze.** Writers now use `ciroh-rti-hefs-data-use1`.

## 6. Rollback

Before step 5.5, nothing about the old bucket has changed, so revert the hefs-fews-hub release. After step 5.5,
also restore the old policy by running the same command without the `MovedToUse1` statement. Anything written to
the new bucket in the meantime has to be copied back by hand: run the step 3 sync in the other direction, without
`--exclude` or `--delete`.

Once step 7 has run there's no rollback: the old bucket and `GEFSv12/` are gone.

## 7. After a soak period: delete the old bucket, `GEFSv12/` included

This can't be undone. Do it once nothing has reported missing data for the soak period. The old bucket has no
request metrics, so CloudWatch can't show whether anything still reads it. If that matters, turn on server access
logging at cutover.

1. Repeat step 4 once more, so the new bucket is known to be complete.
2. Remove the step 5.5 policy. Its `Deny` on `s3:DeleteObject` applies to admins too, so nothing can be deleted
   while it's in place:

   ```bash
   aws s3api delete-bucket-policy --bucket $SRC --region us-east-2
   ```

3. Delete every object, `GEFSv12/` included (about 921k objects, deleted 1,000 per request), then the bucket:

   ```bash
   aws s3 rb s3://$SRC --force --region us-east-2
   ```

   If it's interrupted, run it again.
4. In this repo, remove `ciroh-rti-hefs-data`'s ARNs from `terraform/iceberg-s3-warehouse-readonly-irsa.tf` and
   apply with the `terraform-use1` workflow.

## Open questions

- **Writers:** who has write access to the old bucket now (needs an account admin's IAM export), and which IAM
  users join `teehr-hub-use1-hefs-data-s3-writers`? Is the hefs-fews-hub CI key (`AWI_RTI_HEFS_*`) one of them?
- **Delete permission:** the writers' policy allows `DeleteObject`, since configurations get replaced wholesale.
  Is that wanted, or should deletes be admin-only?
- **Versioning:** the old bucket has none, which matches what was set up here. Hand edits like the 2026-10-29
  `WGRFC_backup` copy suggest a version history would be worth having, with noncurrent versions expiring after
  about 30 days.
- **Soak length:** how long before step 7? The old bucket's public URLs may be in use outside RTI.

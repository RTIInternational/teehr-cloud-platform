# HEFS bucket move: us-east-2 to us-east-1

Runbook for copying the public HEFS-FEWS data bucket `ciroh-rti-hefs-data` (us-east-2, hand-made) to
`ciroh-rti-hefs-data-use1` (us-east-1, `terraform/s3.tf`) and switching its users over
(RTIInternational/teehr-hub#525). The cluster moved on 2026-10-21 (see [region-move.md](region-move.md)), so every
HEFS read from it now crosses regions.

The copy runs on a temporary EC2 instance in the use1 VPC that isn't in Terraform. It's created by hand in step 2
and deleted in step 7.

Code blocks have no comments so they paste cleanly into zsh. The steps need an identity that can create IAM roles
and EC2 instances (`ciroh_mdenno` in the other runbooks), plus the
[Session Manager plugin](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html)
for the AWS CLI.

## What's in the bucket (2026-11-16)

| | |
|---|---|
| Size | 9.08 TB, 921,519 objects, none over 5 GB |
| Largest prefix | `GEFSv12/`: 8.8 TB, 250k objects, last written 2025-07-22 |
| Last write | 2026-10-30 (`HEFS_FEWS/WGRFC`, `ohdPlugins/` in four RFCs, `FIRO/`) |
| Writers | People with their own IAM credentials, by hand. No workflow or cluster role writes to it. |
| Readers | Public `GetObject`. hefs-fews-hub downloads `HEFS_FEWS/<RFC>`. The Jupyter IRSA role can list. |
| Settings | Public-read bucket policy, ACLs blocked, `BucketOwnerEnforced`, SSE-S3, no versioning, no lifecycle |

The new bucket has the same settings, plus a rule that aborts incomplete multipart uploads after 7 days.

**Why EC2 and not a pod:** a pod would need an IRSA role, which is either more Terraform or a hand-made OIDC trust.
It would also be at risk from spot reclaims and the autoscaler for the hours the copy takes. An instance with an
instance profile and Session Manager needs none of that, and deleting it by tag leaves nothing behind. The copy is
server-side (`CopyObject` and `UploadPartCopy`), so the instance only sends requests. It sits in a private subnet,
where the S3 gateway endpoint carries the us-east-1 requests and there are no inbound ports.

**Cost, at list prices:** about $0.01/GB inter-region transfer (Ohio to N. Virginia), so about $91 for everything
or about $3 without `GEFSv12/`. Copy requests cost a few dollars, the instance under $10, and each copy costs about
$209/month to store until the old bucket is deleted.

```bash
export AWS_PROFILE=ciroh_mdenno AWS_REGION=us-east-1
SRC=ciroh-rti-hefs-data
DST=ciroh-rti-hefs-data-use1
NAME=hefs-bucket-copy
```

## 1. Create the bucket (Terraform)

Run the `terraform-use1` workflow (Actions, Run workflow) on `main` after the PR merges, leaving `targets` empty.
The plan should add the bucket and its settings, the `teehr-hub-use1-hefs-data-write` policy and
`teehr-hub-use1-hefs-data-writers` group, and update `teehr-hub-use1-iceberg-s3-warehouse-readonly` in place to
add the new bucket. It should change nothing else.

Check:

```bash
aws s3api get-bucket-location --bucket $DST
aws s3api get-bucket-policy --bucket $DST --query Policy --output text
aws s3api get-public-access-block --bucket $DST
```

## 2. Create the copy instance

An IAM role with read on the source and write on the destination, plus Session Manager:

```bash
cat > /tmp/$NAME-trust.json <<'EOF'
{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ec2.amazonaws.com"},"Action":"sts:AssumeRole"}]}
EOF
cat > /tmp/$NAME-s3.json <<EOF
{"Version":"2012-10-17","Statement":[
 {"Effect":"Allow","Action":["s3:ListBucket","s3:GetBucketLocation"],"Resource":["arn:aws:s3:::$SRC","arn:aws:s3:::$DST"]},
 {"Effect":"Allow","Action":["s3:GetObject","s3:GetObjectTagging"],"Resource":"arn:aws:s3:::$SRC/*"},
 {"Effect":"Allow","Action":["s3:GetObject","s3:PutObject","s3:PutObjectTagging","s3:DeleteObject","s3:AbortMultipartUpload","s3:ListMultipartUploadParts"],"Resource":"arn:aws:s3:::$DST/*"}
]}
EOF
aws iam create-role --role-name $NAME --assume-role-policy-document file:///tmp/$NAME-trust.json --tags Key=Purpose,Value=teehr-hub-525
aws iam put-role-policy --role-name $NAME --policy-name s3-copy --policy-document file:///tmp/$NAME-s3.json
aws iam attach-role-policy --role-name $NAME --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
aws iam create-instance-profile --instance-profile-name $NAME
aws iam add-role-to-instance-profile --instance-profile-name $NAME --role-name $NAME
```

A private subnet in the use1 VPC (us-east-1c, where the node groups run) and a security group with no inbound
rules:

```bash
VPC=$(aws ec2 describe-vpcs --filters Name=tag:Name,Values=teehr-hub-use1-vpc --query 'Vpcs[0].VpcId' --output text)
SUBNET=$(aws ec2 describe-subnets --filters Name=vpc-id,Values=$VPC Name=availability-zone,Values=us-east-1c Name=tag:Name,Values='*private*' --query 'Subnets[0].SubnetId' --output text)
SG=$(aws ec2 create-security-group --group-name $NAME --description "HEFS bucket copy (teehr-hub#525), egress only" --vpc-id $VPC --query GroupId --output text)
echo $VPC $SUBNET $SG
```

An Amazon Linux 2023 instance, which comes with the AWS CLI v2 and the SSM agent. The data never passes through
it, so its network and disk don't matter. What it needs is steady CPU for the CLI's request threads, which is why
it's a `c7i.large` (2 vCPU) and not a burstable `t3`/`t4g`: those run out of CPU credits on a multi-hour copy and
slow to their baseline. Allow about a minute after
`create-instance-profile` before launching, or the launch can fail on the profile:

```bash
AMI=$(aws ssm get-parameter --name /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 --query Parameter.Value --output text)
IID=$(aws ec2 run-instances --image-id $AMI --instance-type c7i.large --subnet-id $SUBNET --security-group-ids $SG \
  --iam-instance-profile Name=$NAME --metadata-options HttpTokens=required \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$NAME},{Key=Purpose,Value=teehr-hub-525}]" \
  --query 'Instances[0].InstanceId' --output text)
aws ec2 wait instance-status-ok --instance-ids $IID
aws ssm start-session --target $IID
```

## 3. Bulk copy (on the instance)

Run the copy in tmux so it survives a dropped session. Reconnect with `aws ssm start-session --target $IID`, then
`sudo su - ec2-user -c 'tmux attach'`.

```bash
sudo dnf install -y tmux
sudo su - ec2-user
tmux new -s copy
```

```bash
SRC=ciroh-rti-hefs-data
DST=ciroh-rti-hefs-data-use1
aws configure set default.s3.max_concurrent_requests 64
aws configure set default.s3.max_queue_size 10000
aws configure set default.s3.multipart_chunksize 64MB
time aws s3 sync s3://$SRC s3://$DST --source-region us-east-2 --region us-east-1 --only-show-errors 2>&1 | tee -a sync-$(date -u +%Y%m%dT%H%M%SZ).log
```

To leave out a prefix (see [Open questions](#open-questions), e.g. `GEFSv12/`), add `--exclude "GEFSv12/*"` to this
sync and every later one.

The sync is incremental. If it stops, run it again and it skips objects that already match by size and timestamp.
After half an hour, check progress from your laptop with
`aws s3 ls s3://$DST --recursive --summarize | tail -2` (slow on large prefixes) or the bucket's CloudWatch
metrics (updated daily). If it's much slower than about 300 MB/s and `top` shows the `aws` process using a full core,
try `max_concurrent_requests` 128 on a `c7i.xlarge`.

## 4. Verify (on the instance)

Compare keys and sizes. ETags can differ for multipart copies, so they aren't compared.

```bash
aws s3api list-objects-v2 --bucket $SRC --region us-east-2 --query 'Contents[].[Key,Size]' --output text | sort > src.tsv
aws s3api list-objects-v2 --bucket $DST --region us-east-1 --query 'Contents[].[Key,Size]' --output text | sort > dst.tsv
wc -l src.tsv dst.tsv
diff src.tsv dst.tsv | head -50
```

Anyone can read objects, but listing needs credentials. From your laptop:

```bash
KEY=$(aws s3api list-objects-v2 --bucket $DST --prefix HEFS_FEWS/ --max-items 1 --query 'Contents[0].Key' --output text)
curl -s -o /dev/null -w '%{http_code}\n' "https://$DST.s3.us-east-1.amazonaws.com/$KEY"
curl -s -o /dev/null -w '%{http_code}\n' "https://$DST.s3.us-east-1.amazonaws.com/?list-type=2"
```

The first should print 200 and the second 403.

## 5. Cutover

1. **Freeze writes** to `ciroh-rti-hefs-data`: tell everyone who writes to it, then wait for confirmation.
2. **Final sync** on the instance. Do a dry run first, so the deletes (objects removed from the source since the
   bulk copy) can be reviewed:

   ```bash
   aws s3 sync s3://$SRC s3://$DST --source-region us-east-2 --region us-east-1 --delete --dryrun | tee final-dryrun.log | grep -c delete
   aws s3 sync s3://$SRC s3://$DST --source-region us-east-2 --region us-east-1 --delete --only-show-errors 2>&1 | tee -a final-sync.log
   ```

   Then repeat step 4.
3. **Switch readers.** In RTIInternational/hefs-fews-hub, change `BUCKET_NAME` in
   `src/hefs_fews_hub/dashboard_funcs.py` and `panel_dashboard.py` to `ciroh-rti-hefs-data-use1`, and
   `AWS_DEFAULT_REGION` in `entrypoint.sh`, `.env.example` and `docs/AWS_SETUP.md` to `us-east-1`. Update the bucket
   name in `docs/notes.md`. Release a new image, then point the HEFS profile choices in teehr-hub (generated by
   `teehr-cloud-core/jupyterhub-profiles/generate_profile_list.py`) at the new tag. Also update the `wget` URL in
   RTIInternational/teehr `playground/metrics/calculate_reference_forecast.ipynb`.
4. **Switch writers.** Add each writer's IAM user to the group:

   ```bash
   aws iam add-user-to-group --group-name teehr-hub-use1-hefs-data-writers --user-name <user>
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
the new bucket in the meantime has to be copied back by hand: run the step 3 sync in the other direction without
`--delete`.

## 7. Delete the copy instance and its IAM

From your laptop, once step 5 is done. Nothing else in the account has the `teehr-hub-525` tag.

```bash
aws ec2 terminate-instances --instance-ids $IID
aws ec2 wait instance-terminated --instance-ids $IID
aws ec2 delete-security-group --group-id $SG
aws iam remove-role-from-instance-profile --instance-profile-name $NAME --role-name $NAME
aws iam delete-instance-profile --instance-profile-name $NAME
aws iam detach-role-policy --role-name $NAME --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
aws iam delete-role-policy --role-name $NAME --policy-name s3-copy
aws iam delete-role --role-name $NAME
aws resourcegroupstaggingapi get-resources --tag-filters Key=Purpose,Values=teehr-hub-525 --query 'ResourceTagMappingList[].ResourceARN'
```

The last command should print `[]`. (Terminated instances can show for up to an hour.)

## 8. After a soak period

- Delete `ciroh-rti-hefs-data` (us-east-2) once nothing reads it. The bucket's daily `GetRequests` CloudWatch
  metrics need request metrics turned on, so check for missing-data reports from users instead, or turn on server
  access logging for the soak.
- Remove the old bucket's ARNs from `terraform/iceberg-s3-warehouse-readonly-irsa.tf`.

## Open questions

- **`GEFSv12/`:** 97% of the data (8.8 TB) and untouched since 2025-07. Nothing in RTIInternational reads it by
  name. Does it move, stay in us-east-2, or go to a cheaper storage class? Leaving it out cuts the copy cost from
  about $91 to $3 and saves about $200/month of storage.
- **Writers:** who has write access to the old bucket now (needs an account admin's IAM export), and which IAM
  users join `teehr-hub-use1-hefs-data-writers`? Is the hefs-fews-hub CI key (`AWI_RTI_HEFS_*`) one of them?
- **Delete permission:** the writers' policy allows `DeleteObject`, since configurations get replaced wholesale.
  Is that wanted, or should deletes be admin-only?
- **Versioning:** the old bucket has none, which matches what was set up here. Hand edits like the 2026-10-29
  `WGRFC_backup` copy suggest a version history would be worth having, with noncurrent versions expiring after
  about 30 days.
- **Old bucket:** after the soak, delete it, or keep it read-only for anyone outside RTI with the old URLs?
- **Who runs it:** the steps need IAM and EC2 create permissions, so an account admin (or someone given them
  for this) runs steps 2-7.

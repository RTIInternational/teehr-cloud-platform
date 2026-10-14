# Maintenance page

`teehr.rtiamanzi.org` is delegated from Azure DNS to a Route 53 zone (`terraform/global/dns.tf`). Every app host
resolves through a `*.teehr.rtiamanzi.org` alias that points either at the Envoy ELB or, when
`maintenance_mode = true`, at a CloudFront distribution serving a static page from S3
(`terraform/global/maintenance.tf`). None of this runs in the cluster.

- Browsers get the page with HTTP 503. API clients (anything not sending `Accept: text/html`) get a JSON 503.
- `https://status.teehr.rtiamanzi.org` always serves from CloudFront and returns 200.
- `https://status.teehr.rtiamanzi.org/status.json` is `{"maintenance": bool, "message": str}`, CORS-enabled, for
  app banners.

All commands here run in `terraform/global`, which holds only these account-wide resources, so `-target` isn't
needed. **Every apply there sets `status.json` from `-var maintenance_message`**: while a banner is up, pass the
current message on every apply, or the banner clears.

## One-time setup

This was done before the resources moved from `terraform/` to `terraform/global/`; it's kept for reference.

The ACM certificate can't validate until the delegation is live, so apply in two steps.

1. Check the `rtiamanzi.org` zone in Azure for any records under `teehr` other than the `*.teehr` CNAME.
   Add them to `dns.tf` before going further.
2. Create the zone and the wildcard record only:

   ```bash
   terraform apply -var-file=teehr-hub.tfvars \
     -target=aws_route53_zone.teehr -target=aws_route53_record.wildcard
   terraform output teehr_zone_name_servers
   ```

3. Check that the new zone answers correctly before anyone uses it:

   ```bash
   dig +short hub.teehr.rtiamanzi.org @<one-of-the-name-servers>   # ELB IPs
   ```

4. In Azure, add an NS record set `teehr` in `rtiamanzi.org` with the four name servers (TTL 3600). Once
   `dig +short NS teehr.rtiamanzi.org` returns the Route 53 servers, delete the Azure `*.teehr` CNAME.
5. Create the rest. It waits for ACM validation, then creates the bucket and the CloudFront distribution. Expect
   5–15 minutes:

   ```bash
   terraform apply -var-file=teehr-hub.tfvars \
     -target=aws_route53_record.status -target=aws_s3_bucket_policy.maintenance \
     -target=aws_s3_bucket_public_access_block.maintenance \
     -target=aws_s3_object.maintenance_index -target=aws_s3_object.maintenance_status
   ```

Rollback before step 4: `terraform destroy -target=aws_route53_zone.teehr`. After step 4: delete the Azure NS
record and restore the `*.teehr` CNAME to the ELB hostname.

## Planned maintenance

1. Ahead of time, announce it:

   ```bash
   terraform apply -var-file=teehr-hub.tfvars \
     -var 'maintenance_message=TEEHR will be down for maintenance Sat Nov 1, 9am–5pm ET.'
   ```

2. At the start of the window, turn on maintenance mode. The alias TTL is 60s:

   ```bash
   terraform apply -var-file=teehr-hub.tfvars -var maintenance_mode=true \
     -var 'maintenance_message=...'
   ```

3. While in maintenance, reach the cluster directly to check it, bypassing DNS:

   ```bash
   ELB=$(kubectl -n projectcontour get svc envoy -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
   curl --resolve hub.teehr.rtiamanzi.org:443:$(dig +short $ELB | head -1) https://hub.teehr.rtiamanzi.org/
   ```

4. Turn it off with `terraform apply -var-file=teehr-hub.tfvars`, without the `-var` overrides.

cert-manager HTTP-01 renewals fail while maintenance mode is on. That's harmless for short windows, since
certificates renew 30 days before expiry.

## Region move

The wildcard alias points at `ingress_elb_hostname` / `ingress_elb_region` in `terraform/global/teehr-hub.tfvars`.
To move DNS to another regional stack, set them from that stack's `ingress_elb_hostname` output and apply in
`terraform/global`. The maintenance bucket stays in us-east-2; it doesn't depend on any cluster.

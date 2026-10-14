region = "us-east-2"

name = "teehr-hub"

environment = "dev"

project_name = "teehr"

# Envoy load balancer of the active regional stack (`terraform output
# ingress_elb_hostname` in ../). Changing these is the DNS cutover.
ingress_elb_hostname = "af55ad7d6786c4889a7dea3336d2f79e-2141472567.us-east-2.elb.amazonaws.com"
ingress_elb_region   = "us-east-2"

region = "us-east-2"

name = "teehr-hub"

environment = "dev"

project_name = "teehr"

# Envoy load balancer of the active regional stack (`terraform output
# ingress_elb_hostname` in ../). Changing these is the DNS cutover.
ingress_elb_hostname = "a606f609594ab4531ba7b225a3418667-154235153.us-east-1.elb.amazonaws.com"
ingress_elb_region   = "us-east-1"

staging_ingress = {
  use1 = {
    elb_hostname = "a606f609594ab4531ba7b225a3418667-154235153.us-east-1.elb.amazonaws.com"
    elb_region   = "us-east-1"
  }
}

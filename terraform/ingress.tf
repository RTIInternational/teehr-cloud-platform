# The Classic ELB created by the Envoy LoadBalancer Service in contour.yaml.
# global/ points *.<zone> at it via its ingress_elb_* variables.
data "kubernetes_service_v1" "envoy" {
  metadata {
    name      = "envoy"
    namespace = "projectcontour"
  }
}

output "ingress_elb_hostname" {
  # Null until Contour's Envoy Service has a load balancer (e.g. a new stack).
  value       = try(data.kubernetes_service_v1.envoy.status[0].load_balancer[0].ingress[0].hostname, null)
  description = "Envoy load balancer hostname, for global/'s ingress_elb_hostname"
}

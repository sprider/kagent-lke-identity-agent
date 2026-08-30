output "kubeconfig" {
  description = "Base64-decoded kubeconfig for the LKE cluster"
  value       = base64decode(linode_lke_cluster.demo.kubeconfig)
  sensitive   = true
}

output "cluster_id" {
  description = "ID of the LKE cluster"
  value       = linode_lke_cluster.demo.id
}

output "cluster_status" {
  description = "Status of the LKE cluster"
  value       = linode_lke_cluster.demo.status
}

output "keycloak_namespace" {
  description = "Namespace where Keycloak is deployed"
  value       = helm_release.keycloak.namespace
}

output "keycloak_url" {
  description = "URL to access Keycloak once the LoadBalancer IP is assigned"
  value       = local.keycloak_url_host != "" ? local.keycloak_url_host : "LoadBalancer IP not yet assigned"
}

output "keycloak_admin_console_url" {
  description = "URL to access the Keycloak admin console"
  value       = local.keycloak_url_host != "" ? "${local.keycloak_url_host}/admin" : "LoadBalancer IP not yet assigned"
}

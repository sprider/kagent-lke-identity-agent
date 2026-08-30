variable "linode_token" {
  description = "Linode API token with permission to create LKE clusters"
  type        = string
  sensitive   = true
}

variable "cluster_label" {
  description = "Label for the LKE cluster"
  type        = string
  default     = "kagent-identity-demo"
}

variable "k8s_version" {
  description = "Kubernetes version for the LKE cluster (must be a currently offered LKE version)"
  type        = string
  default     = "1.35"
}

variable "region" {
  description = "Linode region for the LKE cluster"
  type        = string
  default     = "us-east"
}

variable "node_type" {
  description = "Linode worker node type (Keycloak needs at least 4GB RAM)"
  type        = string
  default     = "g6-standard-4"
}

variable "node_count" {
  description = "Number of worker nodes"
  type        = number
  default     = 3
}

variable "tags" {
  description = "Tags to apply to the LKE cluster"
  type        = list(string)
  default     = ["kagent", "identity-agent", "demo"]
}

variable "keycloak_namespace" {
  description = "Kubernetes namespace for Keycloak"
  type        = string
  default     = "keycloak"
}

variable "keycloak_admin_user" {
  description = "Keycloak admin username"
  type        = string
  default     = "admin"
}

variable "keycloak_admin_password" {
  description = "Keycloak admin password"
  type        = string
  sensitive   = true
}

variable "keycloak_service_type" {
  description = "Keycloak Kubernetes service type"
  type        = string
  default     = "LoadBalancer"
}

variable "keycloak_chart_version" {
  description = "Version of the bitnami/keycloak Helm chart"
  type        = string
  default     = "24.0.0"
}

variable "keycloak_replica_count" {
  description = "Number of Keycloak replicas"
  type        = number
  default     = 1
}

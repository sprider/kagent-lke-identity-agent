resource "kubernetes_namespace" "keycloak" {
  metadata {
    name = var.keycloak_namespace
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  depends_on = [linode_lke_cluster.demo]
}

resource "helm_release" "keycloak" {
  name       = "keycloak"
  repository = "https://charts.bitnami.com/bitnami"
  chart      = "keycloak"
  version    = var.keycloak_chart_version
  namespace  = kubernetes_namespace.keycloak.metadata[0].name

  set {
    name  = "image.registry"
    value = "docker.io"
  }

  set {
    name  = "image.repository"
    value = "bitnamilegacy/keycloak"
  }

  set {
    name  = "postgresql.image.registry"
    value = "docker.io"
  }

  set {
    name  = "postgresql.image.repository"
    value = "bitnamilegacy/postgresql"
  }

  set {
    name  = "keycloakConfigCli.image.registry"
    value = "docker.io"
  }

  set {
    name  = "keycloakConfigCli.image.repository"
    value = "bitnamilegacy/keycloak-config-cli"
  }

  set {
    name  = "auth.adminUser"
    value = var.keycloak_admin_user
  }

  set_sensitive {
    name  = "auth.adminPassword"
    value = var.keycloak_admin_password
  }

  set {
    name  = "service.type"
    value = var.keycloak_service_type
  }

  set {
    name  = "replicaCount"
    value = var.keycloak_replica_count
  }

  timeout = 900
  wait    = true

  depends_on = [
    linode_lke_cluster.demo,
    kubernetes_namespace.keycloak,
  ]
}

data "kubernetes_service" "keycloak" {
  metadata {
    name      = "keycloak"
    namespace = helm_release.keycloak.namespace
  }

  depends_on = [helm_release.keycloak]
}

locals {
  keycloak_lb_ip = (
    length(data.kubernetes_service.keycloak.status) > 0 &&
    length(data.kubernetes_service.keycloak.status[0].load_balancer) > 0 &&
    length(data.kubernetes_service.keycloak.status[0].load_balancer[0].ingress) > 0
  ) ? data.kubernetes_service.keycloak.status[0].load_balancer[0].ingress[0].ip : ""

  keycloak_http_port = (
    length(data.kubernetes_service.keycloak.spec) > 0 &&
    length(data.kubernetes_service.keycloak.spec[0].port) > 0
  ) ? data.kubernetes_service.keycloak.spec[0].port[0].port : 80

  keycloak_url_host = local.keycloak_lb_ip != "" ? (
    local.keycloak_http_port == 80 ?
    "http://${local.keycloak_lb_ip}" :
    "http://${local.keycloak_lb_ip}:${local.keycloak_http_port}"
  ) : ""
}

terraform {
  required_version = ">= 1.5"

  required_providers {
    linode = {
      source  = "linode/linode"
      version = "~> 2.30"
    }

    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.15"
    }

    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.31"
    }
  }
}

provider "linode" {
  token = var.linode_token
}

provider "kubernetes" {
  config_path = pathexpand("~/.kube/kagent-identity-config")
}

provider "helm" {
  kubernetes {
    config_path = pathexpand("~/.kube/kagent-identity-config")
  }
}

resource "linode_lke_cluster" "demo" {
  label       = var.cluster_label
  k8s_version = var.k8s_version
  region      = var.region
  tags        = var.tags

  pool {
    type  = var.node_type
    count = var.node_count
  }
}

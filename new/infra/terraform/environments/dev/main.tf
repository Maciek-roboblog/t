# Development Environment
# LLM Platform - Dev

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.25"
    }
  }

  backend "gcs" {
    bucket = "llm-platform-tfstate-dev"
    prefix = "terraform/state"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

provider "google-beta" {
  project = var.project_id
  region  = var.region
}

# Kubernetes provider - konfigurowany po utworzeniu klastra
provider "kubernetes" {
  host                   = "https://${module.gke.cluster_endpoint}"
  cluster_ca_certificate = base64decode(module.gke.cluster_ca_certificate)
  token                  = data.google_client_config.default.access_token
}

provider "helm" {
  kubernetes {
    host                   = "https://${module.gke.cluster_endpoint}"
    cluster_ca_certificate = base64decode(module.gke.cluster_ca_certificate)
    token                  = data.google_client_config.default.access_token
  }
}

data "google_client_config" "default" {}

# Networking
module "networking" {
  source = "../../modules/networking"

  project_id   = var.project_id
  region       = var.region
  network_name = "llm-platform-dev-vpc"
  subnet_name  = "llm-platform-dev-subnet"
  subnet_cidr  = "10.0.0.0/20"
  pods_cidr    = "10.16.0.0/14"
  services_cidr = "10.20.0.0/20"
}

# GKE Cluster
module "gke" {
  source = "../../modules/gke"

  project_id   = var.project_id
  region       = var.region
  cluster_name = "llm-platform-dev"

  network_id   = module.networking.network_id
  subnetwork_id = module.networking.subnet_id
  pods_range_name = module.networking.pods_range_name
  services_range_name = module.networking.services_range_name

  # Dev - mniejsze zasoby
  standard_node_count = 2
  standard_min_nodes  = 1
  standard_max_nodes  = 5
  standard_machine_type = "e2-standard-4"

  gpu_min_nodes = 0
  gpu_max_nodes = 2
  gpu_machine_type = "a2-highgpu-1g"
  gpu_type = "nvidia-tesla-a100"
  gpu_count_per_node = 1

  release_channel = "RAPID"

  labels = {
    "environment" = "dev"
    "managed-by"  = "terraform"
    "project"     = "llm-platform"
  }
}

# Storage
module "storage" {
  source = "../../modules/storage"

  project_id = var.project_id
  region     = var.region
  network_id = module.networking.network_id

  sql_instance_name = "llm-platform-mlflow-dev"
  sql_tier          = "db-custom-1-3840"  # Mniejsza instancja dla dev
  sql_availability_type = "ZONAL"         # Bez HA dla dev
  sql_disk_size     = 20
  sql_user          = "mlflow"
  sql_password      = var.sql_password

  artifact_registry_name = "llm-platform-dev"
  deletion_protection = false  # Dev można usuwać

  private_vpc_connection = module.networking

  labels = {
    "environment" = "dev"
    "managed-by"  = "terraform"
  }
}

# IAM
module "iam" {
  source = "../../modules/iam"

  project_id = var.project_id
  workload_sa_name = "llm-workload-dev"
  cicd_sa_name = "llm-cicd-dev"

  workspace_names = var.workspace_names
}

# Outputs
output "cluster_name" {
  value = module.gke.cluster_name
}

output "cluster_endpoint" {
  value     = module.gke.cluster_endpoint
  sensitive = true
}

output "sql_private_ip" {
  value = module.storage.sql_private_ip
}

output "mlflow_bucket" {
  value = module.storage.mlflow_common_bucket_url
}

output "artifact_registry" {
  value = module.storage.artifact_registry_url
}

output "workload_sa_email" {
  value = module.iam.workload_sa_email
}

output "kubectl_command" {
  value = "gcloud container clusters get-credentials ${module.gke.cluster_name} --region ${var.region} --project ${var.project_id}"
}

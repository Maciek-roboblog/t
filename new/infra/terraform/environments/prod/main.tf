# Production Environment
# LLM Platform - Prod

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
    bucket = "llm-platform-tfstate-prod"
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
  network_name = "llm-platform-prod-vpc"
  subnet_name  = "llm-platform-prod-subnet"
  subnet_cidr  = "10.0.0.0/20"
  pods_cidr    = "10.16.0.0/14"
  services_cidr = "10.20.0.0/20"
}

# GKE Cluster
module "gke" {
  source = "../../modules/gke"

  project_id   = var.project_id
  region       = var.region
  cluster_name = "llm-platform-prod"

  network_id   = module.networking.network_id
  subnetwork_id = module.networking.subnet_id
  pods_range_name = module.networking.pods_range_name
  services_range_name = module.networking.services_range_name

  # Prod - większe zasoby
  standard_node_count = 3
  standard_min_nodes  = 3
  standard_max_nodes  = 15
  standard_machine_type = "e2-standard-8"

  gpu_min_nodes = 1  # Zawsze min 1 GPU dla inference
  gpu_max_nodes = 8
  gpu_machine_type = "a2-highgpu-1g"
  gpu_type = "nvidia-tesla-a100"
  gpu_count_per_node = 1

  release_channel = "REGULAR"  # Stabilniejszy channel dla prod

  labels = {
    "environment" = "prod"
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

  sql_instance_name = "llm-platform-mlflow-prod"
  sql_tier          = "db-custom-4-16384"  # 4 vCPU, 16GB RAM
  sql_availability_type = "REGIONAL"       # HA dla prod
  sql_disk_size     = 100
  sql_user          = "mlflow"
  sql_password      = var.sql_password

  artifact_registry_name = "llm-platform-prod"
  deletion_protection = true  # Ochrona przed usunięciem

  private_vpc_connection = module.networking

  labels = {
    "environment" = "prod"
    "managed-by"  = "terraform"
  }
}

# IAM
module "iam" {
  source = "../../modules/iam"

  project_id = var.project_id
  workload_sa_name = "llm-workload-prod"
  cicd_sa_name = "llm-cicd-prod"

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

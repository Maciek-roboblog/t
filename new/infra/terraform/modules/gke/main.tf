# GKE Cluster Module
# Klaster z GPU node pool dla LLM workloads

terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.0"
    }
  }
}

# GKE Cluster
resource "google_container_cluster" "llm_cluster" {
  provider = google-beta

  name     = var.cluster_name
  location = var.region

  # Usuń domyślny node pool
  remove_default_node_pool = true
  initial_node_count       = 1

  # Networking
  network    = var.network_id
  subnetwork = var.subnetwork_id

  # Workload Identity
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  # Private cluster
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = var.master_ipv4_cidr_block
  }

  # IP allocation
  ip_allocation_policy {
    cluster_secondary_range_name  = var.pods_range_name
    services_secondary_range_name = var.services_range_name
  }

  # Addons
  addons_config {
    http_load_balancing {
      disabled = false
    }
    horizontal_pod_autoscaling {
      disabled = false
    }
    gce_persistent_disk_csi_driver_config {
      enabled = true
    }
  }

  # Maintenance window
  maintenance_policy {
    daily_maintenance_window {
      start_time = "03:00"
    }
  }

  # Logging & Monitoring
  logging_config {
    enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS"]
  }

  monitoring_config {
    enable_components = ["SYSTEM_COMPONENTS"]
    managed_prometheus {
      enabled = true
    }
  }

  # Release channel
  release_channel {
    channel = var.release_channel
  }

  resource_labels = var.labels
}

# Standard Node Pool (dla serwisów bez GPU)
resource "google_container_node_pool" "standard_pool" {
  name       = "standard-pool"
  location   = var.region
  cluster    = google_container_cluster.llm_cluster.name
  node_count = var.standard_node_count

  autoscaling {
    min_node_count = var.standard_min_nodes
    max_node_count = var.standard_max_nodes
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  node_config {
    machine_type = var.standard_machine_type
    disk_size_gb = 100
    disk_type    = "pd-ssd"

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    labels = merge(var.labels, {
      "node-type" = "standard"
    })

    tags = ["llm-cluster", "standard-node"]
  }
}

# GPU Node Pool (A100 dla treningu i inferencji)
resource "google_container_node_pool" "gpu_pool" {
  provider = google-beta

  name     = "gpu-pool"
  location = var.region
  cluster  = google_container_cluster.llm_cluster.name

  # Autoscaling dla GPU
  autoscaling {
    min_node_count = var.gpu_min_nodes
    max_node_count = var.gpu_max_nodes
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  node_config {
    machine_type = var.gpu_machine_type
    disk_size_gb = 200
    disk_type    = "pd-ssd"

    # GPU Configuration
    guest_accelerator {
      type  = var.gpu_type
      count = var.gpu_count_per_node
      gpu_driver_installation_config {
        gpu_driver_version = "LATEST"
      }
    }

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    labels = merge(var.labels, {
      "node-type"                       = "gpu"
      "cloud.google.com/gke-accelerator" = var.gpu_type
    })

    taint {
      key    = "nvidia.com/gpu"
      value  = "present"
      effect = "NO_SCHEDULE"
    }

    tags = ["llm-cluster", "gpu-node"]
  }
}

# NVIDIA GPU Operator (via Helm)
resource "helm_release" "nvidia_gpu_operator" {
  name       = "nvidia-gpu-operator"
  repository = "https://helm.ngc.nvidia.com/nvidia"
  chart      = "gpu-operator"
  namespace  = "gpu-operator"
  version    = var.gpu_operator_version

  create_namespace = true

  set {
    name  = "driver.enabled"
    value = "false" # GKE ma wbudowane drivery
  }

  set {
    name  = "toolkit.enabled"
    value = "true"
  }

  depends_on = [google_container_node_pool.gpu_pool]
}

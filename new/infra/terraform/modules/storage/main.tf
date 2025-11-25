# Storage Module
# Cloud SQL (MLFlow backend), GCS buckets (artifacts), Artifact Registry

# Cloud SQL Instance (PostgreSQL dla MLFlow)
resource "google_sql_database_instance" "mlflow_db" {
  name             = var.sql_instance_name
  database_version = "POSTGRES_15"
  region           = var.region
  project          = var.project_id

  deletion_protection = var.deletion_protection

  settings {
    tier              = var.sql_tier
    availability_type = var.sql_availability_type
    disk_size         = var.sql_disk_size
    disk_type         = "PD_SSD"

    ip_configuration {
      ipv4_enabled    = false
      private_network = var.network_id
    }

    backup_configuration {
      enabled                        = true
      start_time                     = "03:00"
      point_in_time_recovery_enabled = true
      backup_retention_settings {
        retained_backups = 7
      }
    }

    maintenance_window {
      day          = 7 # Sunday
      hour         = 4
      update_track = "stable"
    }

    database_flags {
      name  = "max_connections"
      value = "200"
    }
  }

  depends_on = [var.private_vpc_connection]
}

# Database - MLFlow Common
resource "google_sql_database" "mlflow_common" {
  name     = "mlflow_common"
  instance = google_sql_database_instance.mlflow_db.name
  project  = var.project_id
}

# Database user
resource "google_sql_user" "mlflow_user" {
  name     = var.sql_user
  instance = google_sql_database_instance.mlflow_db.name
  password = var.sql_password
  project  = var.project_id
}

# GCS Bucket - MLFlow Common Artifacts
resource "google_storage_bucket" "mlflow_common" {
  name          = "${var.project_id}-mlflow-common"
  location      = var.region
  project       = var.project_id
  force_destroy = !var.deletion_protection

  uniform_bucket_level_access = true

  versioning {
    enabled = true
  }

  lifecycle_rule {
    condition {
      age = 90
    }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }

  labels = var.labels
}

# Artifact Registry - Docker images
resource "google_artifact_registry_repository" "llm_platform" {
  location      = var.region
  repository_id = var.artifact_registry_name
  description   = "Docker images for LLM Platform"
  format        = "DOCKER"
  project       = var.project_id

  labels = var.labels
}

# GCS Bucket template dla workspace'ów (tworzony dynamicznie)
# Ten bucket jest wzorcem - workspace'y będą miały własne buckety
resource "google_storage_bucket" "mlflow_workspace_template" {
  count = var.create_workspace_bucket_template ? 1 : 0

  name          = "${var.project_id}-mlflow-workspace-template"
  location      = var.region
  project       = var.project_id
  force_destroy = true

  uniform_bucket_level_access = true

  versioning {
    enabled = true
  }

  labels = merge(var.labels, {
    "type" = "template"
  })
}

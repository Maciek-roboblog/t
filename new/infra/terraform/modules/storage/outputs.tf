# Storage Module Outputs

output "sql_instance_name" {
  description = "Cloud SQL instance name"
  value       = google_sql_database_instance.mlflow_db.name
}

output "sql_connection_name" {
  description = "Cloud SQL connection name"
  value       = google_sql_database_instance.mlflow_db.connection_name
}

output "sql_private_ip" {
  description = "Cloud SQL private IP address"
  value       = google_sql_database_instance.mlflow_db.private_ip_address
}

output "mlflow_common_bucket" {
  description = "MLFlow common artifacts bucket"
  value       = google_storage_bucket.mlflow_common.name
}

output "mlflow_common_bucket_url" {
  description = "MLFlow common artifacts bucket URL"
  value       = "gs://${google_storage_bucket.mlflow_common.name}"
}

output "artifact_registry_url" {
  description = "Artifact Registry URL"
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.llm_platform.repository_id}"
}

output "artifact_registry_gcr_url" {
  description = "Artifact Registry GCR-style URL"
  value       = "eu.gcr.io/${var.project_id}"
}

# IAM Module Outputs

output "workload_sa_email" {
  description = "Workload service account email"
  value       = google_service_account.llm_workload.email
}

output "workload_sa_name" {
  description = "Workload service account name"
  value       = google_service_account.llm_workload.name
}

output "cicd_sa_email" {
  description = "CI/CD service account email"
  value       = google_service_account.cicd.email
}

output "cicd_sa_name" {
  description = "CI/CD service account name"
  value       = google_service_account.cicd.name
}

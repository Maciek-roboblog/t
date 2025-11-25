# IAM Module
# Service Accounts, Workload Identity bindings

# Service Account - LLM Workloads
resource "google_service_account" "llm_workload" {
  account_id   = var.workload_sa_name
  display_name = "LLM Platform Workload Identity"
  description  = "Service account for LLM training and inference workloads"
  project      = var.project_id
}

# Service Account - CI/CD
resource "google_service_account" "cicd" {
  account_id   = var.cicd_sa_name
  display_name = "LLM Platform CI/CD"
  description  = "Service account for CI/CD pipelines"
  project      = var.project_id
}

# IAM Roles for Workload SA
resource "google_project_iam_member" "workload_storage_admin" {
  project = var.project_id
  role    = "roles/storage.objectAdmin"
  member  = "serviceAccount:${google_service_account.llm_workload.email}"
}

resource "google_project_iam_member" "workload_artifact_reader" {
  project = var.project_id
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:${google_service_account.llm_workload.email}"
}

resource "google_project_iam_member" "workload_sql_client" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.llm_workload.email}"
}

resource "google_project_iam_member" "workload_logging" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.llm_workload.email}"
}

resource "google_project_iam_member" "workload_monitoring" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.llm_workload.email}"
}

# IAM Roles for CI/CD SA
resource "google_project_iam_member" "cicd_artifact_writer" {
  project = var.project_id
  role    = "roles/artifactregistry.writer"
  member  = "serviceAccount:${google_service_account.cicd.email}"
}

resource "google_project_iam_member" "cicd_gke_developer" {
  project = var.project_id
  role    = "roles/container.developer"
  member  = "serviceAccount:${google_service_account.cicd.email}"
}

resource "google_project_iam_member" "cicd_storage_admin" {
  project = var.project_id
  role    = "roles/storage.objectAdmin"
  member  = "serviceAccount:${google_service_account.cicd.email}"
}

# Workload Identity Binding - llm-shared namespace
resource "google_service_account_iam_member" "workload_identity_shared" {
  service_account_id = google_service_account.llm_workload.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[llm-shared/llm-workload-sa]"
}

# Workload Identity Bindings dla workspace'ów (dynamiczne)
resource "google_service_account_iam_member" "workload_identity_workspaces" {
  for_each = toset(var.workspace_names)

  service_account_id = google_service_account.llm_workload.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[llm-workspace-${each.value}/llm-workload-sa]"
}

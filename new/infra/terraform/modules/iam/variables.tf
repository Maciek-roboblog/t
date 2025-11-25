# IAM Module Variables

variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "workload_sa_name" {
  description = "Workload service account name"
  type        = string
  default     = "llm-workload"
}

variable "cicd_sa_name" {
  description = "CI/CD service account name"
  type        = string
  default     = "llm-cicd"
}

variable "workspace_names" {
  description = "List of workspace names for Workload Identity bindings"
  type        = list(string)
  default     = ["team-alpha"]
}

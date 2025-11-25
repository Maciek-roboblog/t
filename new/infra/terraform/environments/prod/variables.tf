# Prod Environment Variables

variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "region" {
  description = "GCP Region"
  type        = string
  default     = "europe-west4"
}

variable "sql_password" {
  description = "MLFlow database password"
  type        = string
  sensitive   = true
}

variable "workspace_names" {
  description = "List of workspace names"
  type        = list(string)
  default     = ["team-alpha"]
}

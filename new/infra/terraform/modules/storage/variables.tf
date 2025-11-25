# Storage Module Variables

variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "region" {
  description = "GCP Region"
  type        = string
  default     = "europe-west4"
}

variable "network_id" {
  description = "VPC Network ID for private SQL"
  type        = string
}

variable "private_vpc_connection" {
  description = "Private VPC connection dependency"
  type        = any
  default     = null
}

# Cloud SQL
variable "sql_instance_name" {
  description = "Cloud SQL instance name"
  type        = string
  default     = "llm-platform-mlflow"
}

variable "sql_tier" {
  description = "Cloud SQL machine tier"
  type        = string
  default     = "db-custom-2-8192" # 2 vCPU, 8GB RAM
}

variable "sql_availability_type" {
  description = "Cloud SQL availability type"
  type        = string
  default     = "REGIONAL" # HA
}

variable "sql_disk_size" {
  description = "Cloud SQL disk size in GB"
  type        = number
  default     = 50
}

variable "sql_user" {
  description = "Cloud SQL user name"
  type        = string
  default     = "mlflow"
}

variable "sql_password" {
  description = "Cloud SQL user password"
  type        = string
  sensitive   = true
}

# Artifact Registry
variable "artifact_registry_name" {
  description = "Artifact Registry repository name"
  type        = string
  default     = "llm-platform"
}

# Options
variable "deletion_protection" {
  description = "Enable deletion protection"
  type        = bool
  default     = true
}

variable "create_workspace_bucket_template" {
  description = "Create workspace bucket template"
  type        = bool
  default     = false
}

variable "labels" {
  description = "Labels to apply to resources"
  type        = map(string)
  default = {
    "managed-by" = "terraform"
    "project"    = "llm-platform"
  }
}

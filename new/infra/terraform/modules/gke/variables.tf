# GKE Module Variables

variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "region" {
  description = "GCP Region"
  type        = string
  default     = "europe-west4"
}

variable "cluster_name" {
  description = "GKE Cluster name"
  type        = string
  default     = "llm-platform-cluster"
}

# Networking
variable "network_id" {
  description = "VPC Network ID"
  type        = string
}

variable "subnetwork_id" {
  description = "Subnetwork ID"
  type        = string
}

variable "master_ipv4_cidr_block" {
  description = "CIDR block for GKE master"
  type        = string
  default     = "172.16.0.0/28"
}

variable "pods_range_name" {
  description = "Name of the secondary range for pods"
  type        = string
  default     = "pods"
}

variable "services_range_name" {
  description = "Name of the secondary range for services"
  type        = string
  default     = "services"
}

# Standard Node Pool
variable "standard_node_count" {
  description = "Initial node count for standard pool"
  type        = number
  default     = 3
}

variable "standard_min_nodes" {
  description = "Minimum nodes in standard pool"
  type        = number
  default     = 2
}

variable "standard_max_nodes" {
  description = "Maximum nodes in standard pool"
  type        = number
  default     = 10
}

variable "standard_machine_type" {
  description = "Machine type for standard nodes"
  type        = string
  default     = "e2-standard-8"
}

# GPU Node Pool
variable "gpu_min_nodes" {
  description = "Minimum GPU nodes"
  type        = number
  default     = 0
}

variable "gpu_max_nodes" {
  description = "Maximum GPU nodes"
  type        = number
  default     = 4
}

variable "gpu_machine_type" {
  description = "Machine type for GPU nodes"
  type        = string
  default     = "a2-highgpu-1g" # 1x A100 40GB
}

variable "gpu_type" {
  description = "GPU accelerator type"
  type        = string
  default     = "nvidia-tesla-a100"
}

variable "gpu_count_per_node" {
  description = "Number of GPUs per node"
  type        = number
  default     = 1
}

variable "gpu_operator_version" {
  description = "NVIDIA GPU Operator Helm chart version"
  type        = string
  default     = "v23.9.1"
}

# Cluster config
variable "release_channel" {
  description = "GKE release channel"
  type        = string
  default     = "REGULAR"
}

variable "labels" {
  description = "Labels to apply to resources"
  type        = map(string)
  default = {
    "managed-by" = "terraform"
    "project"    = "llm-platform"
  }
}

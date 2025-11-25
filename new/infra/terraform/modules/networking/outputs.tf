# Networking Module Outputs

output "network_id" {
  description = "VPC Network ID"
  value       = google_compute_network.llm_vpc.id
}

output "network_name" {
  description = "VPC Network name"
  value       = google_compute_network.llm_vpc.name
}

output "subnet_id" {
  description = "Subnet ID"
  value       = google_compute_subnetwork.llm_subnet.id
}

output "subnet_name" {
  description = "Subnet name"
  value       = google_compute_subnetwork.llm_subnet.name
}

output "pods_range_name" {
  description = "Pods secondary range name"
  value       = "pods"
}

output "services_range_name" {
  description = "Services secondary range name"
  value       = "services"
}

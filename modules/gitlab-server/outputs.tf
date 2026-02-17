output "internal_ip" {
  description = "Internal IP address of the GitLab server."
  value       = google_compute_instance.gitlab.network_interface[0].network_ip
}

output "instance_name" {
  description = "Name of the GitLab server instance."
  value       = google_compute_instance.gitlab.name
}

output "instance_zone" {
  description = "Zone of the GitLab server instance."
  value       = google_compute_instance.gitlab.zone
}

output "service_account_email" {
  description = "Email of the GitLab server service account."
  value       = google_service_account.gitlab.email
}

output "internal_ip" {
  description = "Internal IP address of the GitLab runner."
  value       = google_compute_instance.runner.network_interface[0].network_ip
}

output "instance_name" {
  description = "Name of the GitLab runner instance."
  value       = google_compute_instance.runner.name
}

output "instance_zone" {
  description = "Zone of the GitLab runner instance."
  value       = google_compute_instance.runner.zone
}

output "service_account_email" {
  description = "Email of the GitLab runner service account."
  value       = google_service_account.runner.email
}

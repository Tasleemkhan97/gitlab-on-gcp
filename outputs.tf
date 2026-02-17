output "gitlab_server_internal_ip" {
  description = "Internal IP address of the GitLab server."
  value       = module.gitlab_server.internal_ip
}

output "gitlab_server_ssh_command" {
  description = "IAP SSH command to connect to the GitLab server."
  value       = "gcloud compute ssh ${module.gitlab_server.instance_name} --zone=${module.gitlab_server.instance_zone} --tunnel-through-iap --project=${var.project_id}"
}

output "gitlab_server_port_forward_command" {
  description = "IAP SSH port-forward command to access GitLab UI at http://localhost:8080."
  value       = "gcloud compute ssh ${module.gitlab_server.instance_name} --zone=${module.gitlab_server.instance_zone} --tunnel-through-iap --project=${var.project_id} -- -L 8080:localhost:80"
}

# output "gitlab_runner_ssh_command" {
#   description = "IAP SSH command to connect to the GitLab runner."
#   value       = "gcloud compute ssh ${module.gitlab_runner.instance_name} --zone=${module.gitlab_runner.instance_zone} --tunnel-through-iap --project=${var.project_id}"
# }

# output "gitlab_runner_internal_ip" {
#   description = "Internal IP address of the GitLab runner."
#   value       = module.gitlab_runner.internal_ip
# }

output "backup_bucket_name" {
  description = "Name of the GCS bucket used for GitLab backups."
  value       = google_storage_bucket.backup.name
}

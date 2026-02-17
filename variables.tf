variable "project_id" {
  description = "GCP project ID."
  type        = string
}

variable "region" {
  description = "GCP region."
  type        = string
  default     = "me-central1"
}

variable "zone" {
  description = "GCP zone."
  type        = string
  default     = "me-central1-a"
}

variable "name_prefix" {
  description = "Prefix for resource names."
  type        = string
  default     = "gitlab"
}

variable "network_self_link" {
  description = "Self link of an existing VPC network. If empty, a new network is created."
  type        = string
  default     = ""
}

variable "subnet_self_link" {
  description = "Self link of an existing subnet. If empty, a new subnet is created."
  type        = string
  default     = ""
}

variable "subnet_cidr" {
  description = "CIDR range for the subnet (used when creating a new subnet or for firewall rules)."
  type        = string
  default     = "10.0.0.0/24"
}

variable "gitlab_external_url" {
  description = "External URL for GitLab. Defaults to http://<internal_ip>."
  type        = string
  default     = ""
}

variable "gitlab_runner_token" {
  description = "GitLab runner authentication token (glrt-*). Create the runner in GitLab Admin > CI/CD > Runners first, then use the generated token."
  type        = string
  sensitive   = true
  default     = "CHANGE_ME"
}

variable "machine_type" {
  description = "Machine type for GitLab server and runner."
  type        = string
  default     = "e2-standard-8"
}

variable "backup_retention_days" {
  description = "Number of days to retain backups in GCS before automatic deletion."
  type        = number
  default     = 30
}

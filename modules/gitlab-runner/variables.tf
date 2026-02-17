variable "project_id" {
  description = "GCP project ID."
  type        = string
}

variable "region" {
  description = "GCP region."
  type        = string
}

variable "zone" {
  description = "GCP zone."
  type        = string
}

variable "network_self_link" {
  description = "Self link of the VPC network."
  type        = string
}

variable "subnet_self_link" {
  description = "Self link of the subnet."
  type        = string
}

variable "machine_type" {
  description = "Machine type for the GitLab runner."
  type        = string
  default     = "e2-standard-8"
}

variable "boot_disk_size" {
  description = "Boot disk size in GB."
  type        = number
  default     = 50
}

variable "gitlab_server_ip" {
  description = "Internal IP of the GitLab server."
  type        = string
}

variable "gitlab_runner_token" {
  description = "GitLab runner authentication token (glrt-*). Create the runner in GitLab UI first, then use the generated token."
  type        = string
  sensitive   = true
}

variable "name_prefix" {
  description = "Prefix for resource names."
  type        = string
  default     = "gitlab"
}

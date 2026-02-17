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
  description = "Machine type for the GitLab server."
  type        = string
  default     = "e2-standard-8"
}

variable "boot_disk_size" {
  description = "Boot disk size in GB."
  type        = number
  default     = 50
}

variable "data_disk_size" {
  description = "Data disk size in GB for GitLab data."
  type        = number
  default     = 100
}

variable "gitlab_external_url" {
  description = "External URL for GitLab. Defaults to http://<internal_ip>."
  type        = string
  default     = ""
}

variable "name_prefix" {
  description = "Prefix for resource names."
  type        = string
  default     = "gitlab"
}

variable "subnet_cidr" {
  description = "CIDR range of the subnet for internal firewall rules."
  type        = string
}

variable "backup_bucket_name" {
  description = "Name of the GCS bucket for GitLab backups and config."
  type        = string
}

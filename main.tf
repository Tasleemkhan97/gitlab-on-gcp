terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 5.0.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# Enable required APIs
resource "google_project_service" "compute" {
  project            = var.project_id
  service            = "compute.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "iap" {
  project            = var.project_id
  service            = "iap.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "storage" {
  project            = var.project_id
  service            = "storage.googleapis.com"
  disable_on_destroy = false
}

# VPC network (created if not provided)
resource "google_compute_network" "vpc" {
  count                   = var.network_self_link == "" ? 1 : 0
  project                 = var.project_id
  name                    = "${var.name_prefix}-network"
  auto_create_subnetworks = false

  depends_on = [google_project_service.compute]
}

resource "google_compute_subnetwork" "subnet" {
  count         = var.subnet_self_link == "" ? 1 : 0
  project       = var.project_id
  name          = "${var.name_prefix}-subnet"
  ip_cidr_range = var.subnet_cidr
  region        = var.region
  network       = local.network_self_link

  private_ip_google_access = true
}

# Cloud Router and NAT for outbound internet (package installs)
resource "google_compute_router" "router" {
  count   = var.network_self_link == "" ? 1 : 0
  project = var.project_id
  name    = "${var.name_prefix}-router"
  region  = var.region
  network = local.network_self_link
}

resource "google_compute_router_nat" "nat" {
  count                              = var.network_self_link == "" ? 1 : 0
  project                            = var.project_id
  name                               = "${var.name_prefix}-nat"
  router                             = google_compute_router.router[0].name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}

locals {
  network_self_link = var.network_self_link != "" ? var.network_self_link : google_compute_network.vpc[0].self_link
  subnet_self_link  = var.subnet_self_link != "" ? var.subnet_self_link : google_compute_subnetwork.subnet[0].self_link
}

# --- Backup infrastructure ---

resource "google_storage_bucket" "backup" {
  project  = var.project_id
  name     = "${var.name_prefix}-backup-${var.project_id}"
  location = var.region

  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  versioning {
    enabled = true
  }

  lifecycle_rule {
    condition {
      age = var.backup_retention_days
    }
    action {
      type = "Delete"
    }
  }

  # Keep noncurrent versions as safety net for overwrites
  lifecycle_rule {
    condition {
      num_newer_versions = 3
      with_state         = "ARCHIVED"
    }
    action {
      type = "Delete"
    }
  }

  depends_on = [google_project_service.storage]
}

module "gitlab_server" {
  source = "./modules/gitlab-server"

  project_id          = var.project_id
  region              = var.region
  zone                = var.zone
  network_self_link   = local.network_self_link
  subnet_self_link    = local.subnet_self_link
  subnet_cidr         = var.subnet_cidr
  machine_type        = var.machine_type
  gitlab_external_url = var.gitlab_external_url
  name_prefix         = var.name_prefix
  backup_bucket_name  = google_storage_bucket.backup.name

  depends_on = [
    google_project_service.compute,
    google_project_service.iap,
    google_project_service.storage,
  ]
}

# module "gitlab_runner" {
#   source = "./modules/gitlab-runner"
#   project_id         = var.project_id
#   region             = var.region
#   zone               = var.zone
#   network_self_link  = local.network_self_link
#   subnet_self_link   = local.subnet_self_link
#   machine_type       = var.machine_type
#   gitlab_server_ip   = module.gitlab_server.internal_ip
#   gitlab_runner_token = var.gitlab_runner_token
#   name_prefix        = var.name_prefix
#   depends_on = [
#     google_project_service.compute,
#     google_project_service.iap,
#   ]
# }

resource "google_service_account" "runner" {
  project      = var.project_id
  account_id   = "${var.name_prefix}-runner-sa"
  display_name = "GitLab Runner Service Account"
}

resource "google_project_iam_member" "runner_log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.runner.email}"
}

resource "google_project_iam_member" "runner_metric_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.runner.email}"
}

resource "google_compute_instance" "runner" {
  project      = var.project_id
  name         = "${var.name_prefix}-runner"
  machine_type = var.machine_type
  zone         = var.zone

  tags = ["${var.name_prefix}-runner"]

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2204-lts"
      size  = var.boot_disk_size
      type  = "pd-ssd"
    }
  }

  network_interface {
    subnetwork = var.subnet_self_link
    # No external IP - access via IAP
  }

  service_account {
    email  = google_service_account.runner.email
    scopes = ["cloud-platform"]
  }

  metadata_startup_script = <<-SCRIPT
    #!/bin/bash
    set -e

    # Install Docker
    apt-get update -y
    apt-get install -y curl apt-transport-https ca-certificates software-properties-common

    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list
    apt-get update -y
    apt-get install -y docker-ce docker-ce-cli containerd.io

    # Install GitLab Runner
    curl -L "https://packages.gitlab.com/install/repositories/runner/gitlab-runner/script.deb.sh" | bash
    apt-get install -y gitlab-runner

    # Register runner with GitLab server using authentication token (glrt-*)
    # See: https://docs.gitlab.com/ee/ci/runners/new_creation_workflow.html
    gitlab-runner register \
      --non-interactive \
      --url "http://${var.gitlab_server_ip}" \
      --token "${var.gitlab_runner_token}" \
      --executor "docker" \
      --docker-image "alpine:latest"
  SCRIPT

  allow_stopping_for_update = true

  lifecycle {
    ignore_changes = [metadata_startup_script]
  }
}

# Allow SSH from IAP
resource "google_compute_firewall" "runner_iap_ssh" {
  project = var.project_id
  name    = "${var.name_prefix}-runner-allow-iap-ssh"
  network = var.network_self_link

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["35.235.240.0/20"]
  target_tags   = ["${var.name_prefix}-runner"]
}

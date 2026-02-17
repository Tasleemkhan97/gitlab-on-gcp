resource "google_service_account" "gitlab" {
  project      = var.project_id
  account_id   = "${var.name_prefix}-server-sa"
  display_name = "GitLab Server Service Account"
}

resource "google_project_iam_member" "gitlab_log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.gitlab.email}"
}

resource "google_project_iam_member" "gitlab_metric_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.gitlab.email}"
}

resource "google_storage_bucket_iam_member" "gitlab_backup" {
  bucket = var.backup_bucket_name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.gitlab.email}"
}

resource "google_compute_disk" "data" {
  project = var.project_id
  name    = "${var.name_prefix}-server-data-11feb"
  type    = "pd-ssd"
  size    = var.data_disk_size
  zone    = var.zone
  snapshot = "manual-snapshot-gitlab-server-data-disk"
}

resource "google_compute_instance" "gitlab" {
  project      = var.project_id
  name         = "${var.name_prefix}-server"
  machine_type = var.machine_type
  zone         = var.zone

  tags = ["${var.name_prefix}-server"]

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2204-lts"
      size  = var.boot_disk_size
      type  = "pd-ssd"
    }
  }

  attached_disk {
    source      = google_compute_disk.data.self_link
    device_name = "gitlab-data" #gitlab-data
  }

  network_interface {
    subnetwork = var.subnet_self_link
    # No external IP - access via IAP
    access_config {
      nat_ip = "34.18.121.90"
      network_tier = "PREMIUM"
    }
  }

  service_account {
    email  = google_service_account.gitlab.email
    scopes = ["cloud-platform"]
  }

  metadata_startup_script = <<-SCRIPT
    #!/bin/bash
    set -e

    DATA_DISK="/dev/disk/by-id/google-gitlab-data"
    DATA_MOUNT="/var/opt/gitlab"
    GCS_CONFIG="gs://${var.backup_bucket_name}/config"

    # --- 1. Mount data disk ---
    while [ ! -e "$DATA_DISK" ]; do sleep 1; done

    if ! blkid "$DATA_DISK"; then
      mkfs.ext4 -m 0 -F -E lazy_itable_init=0,lazy_journal_init=0 "$DATA_DISK"
    fi

    mkdir -p "$DATA_MOUNT"
    if ! mountpoint -q "$DATA_MOUNT"; then
      mount -o discard,defaults "$DATA_DISK" "$DATA_MOUNT"
    fi
    if ! grep -q "google-gitlab-data" /etc/fstab; then
      echo "$DATA_DISK $DATA_MOUNT ext4 discard,defaults,nofail 0 2" >> /etc/fstab
    fi

    # --- 2. Install prerequisites ---
    apt-get update -y
    apt-get install -y curl openssh-server ca-certificates tzdata perl

    if ! command -v gsutil &> /dev/null; then
      curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg \
        | gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg
      echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" \
        > /etc/apt/sources.list.d/google-cloud-sdk.list
      apt-get update -y
      apt-get install -y google-cloud-cli
    fi

    # --- 3. Restore secrets from GCS (if this is a rebuild) ---
    mkdir -p /etc/gitlab
    if gsutil -q stat "$GCS_CONFIG/gitlab-secrets.json" 2>/dev/null; then
      gsutil cp "$GCS_CONFIG/gitlab-secrets.json" /etc/gitlab/gitlab-secrets.json
      gsutil cp "$GCS_CONFIG/gitlab.rb" /etc/gitlab/gitlab.rb 2>/dev/null || true
      chmod 0600 /etc/gitlab/gitlab-secrets.json
    fi

    # --- 4. Install GitLab CE ---
    curl -sS https://packages.gitlab.com/install/repositories/gitlab/gitlab-ce/script.deb.sh | bash

    INTERNAL_IP=$(curl -s -H "Metadata-Flavor: Google" \
      http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/ip)
    EXTERNAL_URL="${var.gitlab_external_url != "" ? var.gitlab_external_url : ""}"
    if [ -z "$EXTERNAL_URL" ]; then
      EXTERNAL_URL="http://$INTERNAL_IP"
    fi

    GITLAB_EXTERNAL_URL="$EXTERNAL_URL" GITLAB_SKIP_RECONFIGURE=true apt-get install -y gitlab-ce

    # --- 5. Configure gitlab.rb (only on fresh install) ---
    if ! grep -q "letsencrypt\['enable'\]" /etc/gitlab/gitlab.rb; then
      echo "letsencrypt['enable'] = false" >> /etc/gitlab/gitlab.rb
    fi
    if ! grep -q "backup_keep_time" /etc/gitlab/gitlab.rb; then
      echo "gitlab_rails['backup_keep_time'] = 604800" >> /etc/gitlab/gitlab.rb
    fi

    # --- 6. Reconfigure and upload secrets to GCS ---
    gitlab-ctl reconfigure

    gsutil cp /etc/gitlab/gitlab-secrets.json "$GCS_CONFIG/gitlab-secrets.json"
    gsutil cp /etc/gitlab/gitlab.rb "$GCS_CONFIG/gitlab.rb"

    # --- 7. Daily backup cron ---
    cat > /etc/cron.d/gitlab-backup << 'CRON'
0 2 * * * root /opt/gitlab-backup.sh >> /var/log/gitlab-backup.log 2>&1
CRON

    cat > /opt/gitlab-backup.sh << 'BACKUP'
#!/bin/bash
set -e
TIMESTAMP=$(date +\%Y\%m\%d)
GCS_BUCKET="${var.backup_bucket_name}"
echo "[$TIMESTAMP] Starting GitLab backup..."
gitlab-backup create CRON=1
LATEST=$(ls -t /var/opt/gitlab/backups/*_gitlab_backup.tar 2>/dev/null | head -1)
if [ -n "$LATEST" ]; then
  gsutil cp "$LATEST" "gs://$GCS_BUCKET/backups/$(basename $LATEST)"
  echo "[$TIMESTAMP] Uploaded $LATEST to GCS"
fi
gsutil cp /etc/gitlab/gitlab-secrets.json "gs://$GCS_BUCKET/config/gitlab-secrets.json"
gsutil cp /etc/gitlab/gitlab.rb "gs://$GCS_BUCKET/config/gitlab.rb"
echo "[$TIMESTAMP] Backup complete"
BACKUP

    chmod 0700 /opt/gitlab-backup.sh
  SCRIPT

  allow_stopping_for_update = true

  # lifecycle {
  #   ignore_changes = [metadata_startup_script]
  # }
}

# Allow SSH from IAP
resource "google_compute_firewall" "gitlab_iap_ssh" {
  project = var.project_id
  name    = "${var.name_prefix}-server-allow-iap-ssh"
  network = var.network_self_link

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["35.235.240.0/20"]
  target_tags   = ["${var.name_prefix}-server"]
}

# Allow HTTP/HTTPS from internal network (for runner communication)
resource "google_compute_firewall" "gitlab_internal_http" {
  project = var.project_id
  name    = "${var.name_prefix}-server-allow-internal-http"
  network = var.network_self_link

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }

  source_ranges = [var.subnet_cidr]
  target_tags   = ["${var.name_prefix}-server"]
}

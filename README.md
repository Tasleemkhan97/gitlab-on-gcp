# GitLab CE on GCP (Omnibus)

Terraform project that deploys a self-hosted GitLab CE (Omnibus) server and a GitLab Runner on Google Cloud Platform using private VMs with no public IPs. All access is through IAP (Identity-Aware Proxy) tunnels.

## Architecture

```
                          ┌─────────────────────────────────────────────┐
                          │              GCP Project                     │
                          │                                             │
                          │   ┌──────────────────────────────────┐      │
  User ──── IAP Tunnel ───┼──►│         VPC Network              │      │
                          │   │    Subnet: 10.0.0.0/24           │      │
                          │   │                                  │      │
                          │   │  ┌──────────────┐  HTTP/HTTPS    │      │
                          │   │  │ GitLab Server │◄────────────┐ │      │
                          │   │  │ e2-standard-8 │             │ │      │
                          │   │  │ No public IP  │             │ │      │
                          │   │  │               │  ┌──────────┴─┤      │
                          │   │  │ Boot: 50 GB   │  │ GitLab     │      │
                          │   │  │ Data: 100 GB  │  │ Runner     │      │
                          │   │  │  (SSD @ /var/ │  │ e2-standard│      │
                          │   │  │   opt/gitlab) │  │ -8         │      │
                          │   │  └──────────────┘  │ No public  │      │
                          │   │                    │ IP          │      │
                          │   │                    │ Boot: 50 GB │      │
                          │   │                    └─────────────┘      │
                          │   │                                  │      │
                          │   └──────────────────────────────────┘      │
                          │                                             │
                          │   Cloud NAT (outbound internet)             │
                          └─────────────────────────────────────────────┘
```

## Design Decisions

### Private-only networking
Both VMs have **no external IP addresses**. This reduces the attack surface by ensuring no services are directly exposed to the internet. All administrative access is routed through GCP's Identity-Aware Proxy (IAP), which enforces authentication and authorization at the network level before any traffic reaches the VMs.

### Separate data disk for GitLab
GitLab data is stored on a dedicated 100 GB persistent SSD mounted at `/var/opt/gitlab`, separate from the 50 GB boot disk. This allows:
- Independent snapshots and backups of GitLab data without capturing the OS.
- Resizing the data disk without recreating the instance.
- Preserving data if the instance is recreated (the disk is a standalone resource).

### Cloud NAT for outbound access
Since the VMs have no public IPs, a Cloud Router + Cloud NAT gateway is provisioned to allow outbound internet access. This is required for the startup scripts to install packages (GitLab CE, Docker, GitLab Runner) from upstream repositories. If you supply an existing VPC, you are responsible for ensuring NAT or equivalent outbound connectivity exists.

### Dedicated service accounts with minimal permissions
Each VM gets its own service account with only `logging.logWriter` and `monitoring.metricWriter` roles. This follows the principle of least privilege -- the VMs can ship logs and metrics to Cloud Operations but cannot access other GCP resources.

### Firewall rules scoped by network tags
- **IAP SSH** (`35.235.240.0/20` on TCP 22) -- applied to both server and runner via their respective tags, allowing `gcloud compute ssh --tunnel-through-iap`.
- **Internal HTTP/HTTPS** (subnet CIDR on TCP 80/443) -- applied only to the GitLab server, allowing the runner to communicate with GitLab's API over the private network.

### Bring-your-own network support
The root module can either create a new VPC + subnet or accept an existing one via `network_self_link` and `subnet_self_link` variables. This makes it easy to integrate into an existing landing zone or shared VPC setup.

### Runner uses Docker executor
The GitLab Runner is configured with the `docker` executor and `alpine:latest` as the default image. Docker is installed on the runner VM during startup. This provides job isolation through containers without requiring Kubernetes.

### Runner authentication tokens (not registration tokens)
This project uses the **new runner creation workflow** introduced in GitLab 15.10. Instead of the deprecated registration token flow (`--registration-token`), you first create the runner in the GitLab UI (Admin > CI/CD > Runners) which gives you an authentication token (`glrt-*`). That token is passed to `gitlab-runner register --token`. Runner metadata like tags and description are managed in the GitLab UI rather than at registration time.

### VM is disposable, data disk + GCS are the source of truth
The startup script is designed so you can delete and recreate the VM at any time without losing data. Application data lives on the data disk under `/var/opt/gitlab/` (PostgreSQL database, Git repositories, uploads, artifacts). Encryption secrets (`gitlab-secrets.json`) and configuration (`gitlab.rb`) are persisted to a GCS bucket.

On VM recreation, the startup script restores secrets and config from GCS **before** installing GitLab, then runs reconfigure. GitLab comes back up with all data intact.

### Startup script idempotency
- The data disk formatting is guarded by a `blkid` check -- only formats on first boot.
- fstab is only appended to if the entry doesn't already exist.
- Config restore happens **before** `apt-get install gitlab-ce` so the package install uses the correct encryption keys from the start.
- Let's Encrypt is disabled since the server runs on a private network with no public DNS.
- `lifecycle { ignore_changes = [metadata_startup_script] }` prevents Terraform from triggering instance replacement on script edits.

## Directory Structure

```
gitlab-on-gcp/
├── main.tf                       # Root: provider, APIs, VPC, NAT, module calls
├── variables.tf                  # Root input variables
├── outputs.tf                    # SSH commands, internal IPs
├── terraform.tfvars.example      # Example variable values
├── README.md
└── modules/
    ├── gitlab-server/
    │   ├── main.tf               # GCE instance, data disk, SA, firewall rules
    │   ├── variables.tf
    │   └── outputs.tf
    └── gitlab-runner/
        ├── main.tf               # GCE instance, Docker, runner registration, firewall
        ├── variables.tf
        └── outputs.tf
```

## Prerequisites

- Terraform >= 1.5.0
- Google Cloud SDK (`gcloud`) authenticated with a project
- A GCP project with billing enabled
- IAM permissions to create compute instances, networks, firewall rules, service accounts, and enable APIs

## Variables

| Variable | Description | Default |
|---|---|---|
| `project_id` | GCP project ID | (required) |
| `region` | GCP region | `me-central1` |
| `zone` | GCP zone | `me-central1-a` |
| `name_prefix` | Prefix for all resource names | `gitlab` |
| `network_self_link` | Existing VPC self link (creates new if empty) | `""` |
| `subnet_self_link` | Existing subnet self link (creates new if empty) | `""` |
| `subnet_cidr` | Subnet CIDR range | `10.0.0.0/24` |
| `gitlab_external_url` | GitLab external URL (defaults to `http://<internal_ip>`) | `""` |
| `gitlab_runner_token` | Runner authentication token (`glrt-*`) from GitLab Admin | `CHANGE_ME` |
| `machine_type` | Machine type for both VMs | `e2-standard-8` |
| `backup_retention_days` | Days to retain backups in GCS before deletion | `30` |

## Deployment Steps

### 1. Configure variables

```bash
cd ~/saudi-company/gitlab-on-gcp
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` and set at minimum:
```hcl
project_id = "your-gcp-project-id"
```

### 2. Initialize and deploy

```bash
terraform init
terraform plan
terraform apply
```

The startup scripts take approximately 5-10 minutes to complete after `terraform apply` finishes. GitLab CE is installed and configured automatically on first boot.

### 3. Access the GitLab UI

Use the IAP SSH tunnel with port forwarding (the command is also available in Terraform outputs):

```bash
gcloud compute ssh gitlab-server \
  --zone=me-central1-a \
  --tunnel-through-iap \
  --project=your-gcp-project-id \
  -- -L 8080:localhost:80
```

Then open **http://localhost:8080** in your browser.

### 4. Get the initial root password

SSH into the GitLab server:

```bash
gcloud compute ssh gitlab-server \
  --zone=me-central1-a \
  --tunnel-through-iap \
  --project=your-gcp-project-id
```

Then retrieve the password:

```bash
sudo cat /etc/gitlab/initial_root_password
```

Log in with username `root` and this password. **Change it immediately** under User Settings > Password.

> The initial password file is automatically deleted after 24 hours by GitLab.

### 5. Register the GitLab Runner

After logging in as root:

1. Navigate to **Admin Area > CI/CD > Runners** and click **New instance runner**.
2. Configure the runner (tags, description, etc.) in the UI and click **Create runner**.
3. GitLab will display an **authentication token** starting with `glrt-`. Copy it.
4. Update `terraform.tfvars`:
   ```hcl
   gitlab_runner_token = "glrt-xxxxxxxxxxxxxxxxxxxx"
   ```
5. Re-apply:
   ```bash
   terraform apply
   ```

The runner VM will be recreated and will register itself with the GitLab server on startup.

> **Note:** This project uses the new runner creation workflow (GitLab 15.10+). The deprecated `--registration-token` flow is not used.

### 6. Verify the runner

In the GitLab UI, go to **Admin Area > CI/CD > Runners** and confirm the runner appears with status **online**.

Alternatively, SSH into the runner:

```bash
gcloud compute ssh gitlab-runner \
  --zone=me-central1-a \
  --tunnel-through-iap \
  --project=your-gcp-project-id
```

```bash
sudo gitlab-runner list
```

## Outputs

| Output | Description |
|---|---|
| `gitlab_server_internal_ip` | Internal IP of the GitLab server |
| `gitlab_server_ssh_command` | Full `gcloud compute ssh` command for the server |
| `gitlab_server_port_forward_command` | SSH command with `-L 8080:localhost:80` for UI access |
| `gitlab_runner_internal_ip` | Internal IP of the runner |
| `gitlab_runner_ssh_command` | Full `gcloud compute ssh` command for the runner |
| `backup_bucket_name` | Name of the GCS backup bucket |

## Resources Created

| Resource | Purpose |
|---|---|
| `google_compute_network` | VPC network (if not provided) |
| `google_compute_subnetwork` | Subnet with Private Google Access (if not provided) |
| `google_compute_router` + `google_compute_router_nat` | Cloud NAT for outbound internet (if not provided) |
| `google_compute_instance` (server) | GitLab CE server |
| `google_compute_disk` | 100 GB SSD data disk for GitLab |
| `google_compute_instance` (runner) | GitLab Runner with Docker |
| `google_service_account` x2 | Dedicated SAs for server and runner |
| `google_compute_firewall` x3 | IAP SSH (x2) + internal HTTP/HTTPS (x1) |
| `google_project_service` x3 | Compute, IAP, Storage APIs |
| `google_storage_bucket` | Backup bucket (versioned, Google-managed encryption) |

## Backup & Disaster Recovery

### What is backed up

| Data | Location | Frequency |
|---|---|---|
| `gitlab-secrets.json` | GCS (`config/`) | Every startup + daily cron |
| `gitlab.rb` | GCS (`config/`) | Every startup + daily cron |
| Database, repos, uploads, artifacts | GCS (`backups/`) | Daily cron at 2:00 AM |

### How it works

A versioned GCS bucket stores config files and full GitLab application backups. The startup script uploads `gitlab-secrets.json` and `gitlab.rb` to GCS after every reconfigure, and a daily cron job uploads full application backups. The bucket retains objects for 30 days (configurable via `backup_retention_days`) and keeps 3 noncurrent versions as a safety net against overwrites.

### Recovery scenarios

**VM dies / recreated** (data disk intact):
No action needed. `terraform apply` recreates the VM. The startup script detects the existing data disk, restores secrets and config from GCS, installs GitLab, and reconfigures. GitLab comes back up with all data.

**Data disk lost** (GCS backups available):
1. Let Terraform recreate the VM and a fresh data disk.
2. SSH into the server and restore secrets from GCS:
   ```bash
   gsutil cp gs://BUCKET/config/gitlab-secrets.json /etc/gitlab/gitlab-secrets.json
   gsutil cp gs://BUCKET/config/gitlab.rb /etc/gitlab/gitlab.rb
   ```
3. Restore the latest application backup:
   ```bash
   gsutil cp gs://BUCKET/backups/TIMESTAMP_gitlab_backup.tar /var/opt/gitlab/backups/
   gitlab-backup restore BACKUP=TIMESTAMP
   ```
4. Reconfigure:
   ```bash
   gitlab-ctl reconfigure
   gitlab-ctl restart
   ```

**Manual backup trigger**:
```bash
sudo /opt/gitlab-backup.sh
```

## Cleanup

```bash
terraform destroy
```

This will remove all resources created by this project. The data disk and all GitLab data will be permanently deleted. GCS backups will also be deleted. To preserve backups, copy them to another bucket before destroying.

# ------------------------------------------------------------------------------
# NETWORK: its own private network, same reasoning as the Azure VNets - kept
# separate from GCP's implicit "default" network, which every new project
# gets automatically and which would otherwise mix this project's traffic
# rules with anything else ever created in the same GCP account.
# ------------------------------------------------------------------------------
resource "google_compute_network" "main" {
  name                    = "vpc-gcp-showcase"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "main" {
  name          = "subnet-gcp-showcase"
  network       = google_compute_network.main.id
  ip_cidr_range = "10.2.0.0/24"
  region        = "us-central1"
}

# ------------------------------------------------------------------------------
# FIREWALL: GCP firewall rules are attached to the network itself, not to a
# subnet or a single machine the way Azure's NSGs are - one global rule set
# for anything running inside this VPC, matched by network "tags" on each
# instance rather than by which subnet it happens to sit in.
# ------------------------------------------------------------------------------
resource "google_compute_firewall" "ssh" {
  name    = "allow-ssh-from-admin"
  network = google_compute_network.main.id

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = [var.admin_source_ip]
  target_tags   = ["gcp-showcase"]
}

resource "google_compute_firewall" "k3s_api" {
  name    = "allow-k3s-api-from-admin"
  network = google_compute_network.main.id

  allow {
    protocol = "tcp"
    ports    = ["6443"]
  }

  source_ranges = [var.admin_source_ip]
  target_tags   = ["gcp-showcase"]
}

# This machine does two jobs at once - the single-node K3s showcase, and
# (separately, as its own independent process, not a K3s workload) the
# Requirement 5 failover proxy. The proxy is the actual public entry point
# for the whole demo, so - unlike the Azure NSGs, where 80/443 only needed
# to reach each region's own Traefik ingress - this rule has to stay open
# to genuinely anywhere, not just Denis's own IP.
resource "google_compute_firewall" "proxy_http" {
  name    = "allow-proxy-http-https-from-anywhere"
  network = google_compute_network.main.id

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["gcp-showcase"]
}

# ------------------------------------------------------------------------------
# IDENTITY: a dedicated service account attached directly to the instance,
# rather than a downloaded JSON key file living on disk anywhere. This is
# GCP's equivalent of Azure's Managed Identity - the VM authenticates to
# GCP's own APIs using this identity automatically, with nothing secret
# ever written to a file that could leak.
# ------------------------------------------------------------------------------
resource "google_service_account" "gcp_showcase" {
  account_id   = "gcp-showcase-vm"
  display_name = "GCP showcase VM - identity, no key file"
}

# ------------------------------------------------------------------------------
# THE VM ITSELF: a single e2-micro instance - the specific size covered by
# GCP's Always Free tier, and only in us-central1, us-west1, or us-east1
# (see providers.tf). Genuinely free, not just cheap, as long as it stays
# exactly this size and exactly in this region.
# ------------------------------------------------------------------------------
resource "google_compute_address" "static_ip" {
  name   = "ip-gcp-showcase"
  region = "us-central1"
}

resource "google_compute_instance" "gcp_showcase" {
  name         = "gcp-showcase"
  machine_type = "e2-micro"
  zone         = "us-central1-a"
  tags         = ["gcp-showcase"]

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2204-lts"
      # The Always Free tier also caps included storage at 30GB standard
      # persistent disk - staying right at that limit keeps this genuinely
      # free rather than just close to it.
      size = 30
      type = "pd-standard"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.main.id
    access_config {
      nat_ip = google_compute_address.static_ip.address
    }
  }

  service_account {
    email  = google_service_account.gcp_showcase.email
    scopes = ["cloud-platform"]
  }

  metadata = {
    ssh-keys = var.admin_ssh_public_key
  }
}

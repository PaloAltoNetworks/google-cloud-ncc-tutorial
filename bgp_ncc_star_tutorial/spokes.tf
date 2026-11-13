# -------------------------------------------------------------------------------------
# Create Spoke1 VPC
# -------------------------------------------------------------------------------------

// Create spoke1 VPC
resource "google_compute_network" "spoke1" {
  name                            = "${local.prefix}spoke1-vpc"
  auto_create_subnetworks         = false
  delete_default_routes_on_create = true
}

// Create spoke1 subnetwork
resource "google_compute_subnetwork" "spoke1_subnet1" {
  name          = "${local.prefix}${var.region}-spoke1"
  ip_cidr_range = var.cidr_spoke1
  region        = var.region
  network       = google_compute_network.spoke1.id

}

// Allow all intra-VPC traffic within the spoke1 VPC
resource "google_compute_firewall" "spoke1" {
  name          = "${local.prefix}spoke1-ingress"
  network       = google_compute_network.spoke1.name
  source_ranges = ["0.0.0.0/0"]

  allow {
    protocol = "all"
    ports    = []
  }
}

// Create spoke1 VM for testing
resource "google_compute_instance" "spoke1_vm1" {
  name                      = "${local.prefix}spoke1-vm1"
  machine_type              = "f1-micro"
  zone                      = data.google_compute_zones.main.names[0]
  can_ip_forward            = false
  allow_stopping_for_update = true

  metadata = {
    serial-port-enable = true
    ssh-keys           = "paloalto:${file(var.public_key_path)}"
  }

  network_interface {
    subnetwork = google_compute_subnetwork.spoke1_subnet1.self_link
    network_ip = cidrhost(var.cidr_spoke1, 10)
  }

  boot_disk {
    initialize_params {
      image = "https://www.googleapis.com/compute/v1/projects/panw-gcp-team-testing/global/images/ubuntu-2004-lts-jenkins"
    }
  }

  service_account {
    scopes = [
      "https://www.googleapis.com/auth/cloud.useraccounts.readonly",
      "https://www.googleapis.com/auth/devstorage.read_only",
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring.write"
    ]
  }
}

# -------------------------------------------------------------------------------------
# Create Spoke2 VPC
# -------------------------------------------------------------------------------------

// Create spoke2 VPC
resource "google_compute_network" "spoke2" {
  name                            = "${local.prefix}spoke2-vpc"
  auto_create_subnetworks         = false
  delete_default_routes_on_create = true
}

// Create spoke2 subnetwork
resource "google_compute_subnetwork" "spoke2_subnet1" {
  name          = "${local.prefix}${var.region}-spoke2"
  ip_cidr_range = var.cidr_spoke2
  region        = var.region
  network       = google_compute_network.spoke2.id
}

// Allow all intra-VPC traffic within the spoke2 VPC
resource "google_compute_firewall" "spoke2" {
  name          = "${local.prefix}spoke2-ingress"
  network       = google_compute_network.spoke2.name
  source_ranges = ["0.0.0.0/0"]

  allow {
    protocol = "all"
    ports    = []
  }
}

// Create spoke2 VM for testing
resource "google_compute_instance" "spoke2_vm1" {
  name                      = "${local.prefix}spoke2-vm1"
  machine_type              = "f1-micro"
  zone                      = data.google_compute_zones.main.names[0]
  can_ip_forward            = false
  allow_stopping_for_update = true

  metadata = {
    serial-port-enable = true
    ssh-keys           = "paloalto:${file(var.public_key_path)}"
  }

  network_interface {
    subnetwork = google_compute_subnetwork.spoke2_subnet1.self_link
    network_ip = cidrhost(var.cidr_spoke2, 10)
  }

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2204-lts"
    }
  }

  service_account {
    scopes = [
      "https://www.googleapis.com/auth/cloud.useraccounts.readonly",
      "https://www.googleapis.com/auth/devstorage.read_only",
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring.write"
    ]
  }
}

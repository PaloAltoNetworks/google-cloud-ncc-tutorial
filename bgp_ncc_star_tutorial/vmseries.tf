# -------------------------------------------------------------------------------------
# Create management and dataplane VPCs, subnets, and firewall rules.
# -------------------------------------------------------------------------------------

// Create management VPC
resource "google_compute_network" "mgmt" {
  name                    = "${local.prefix}mgmt"
  auto_create_subnetworks = false
}

// Create untrust VPC
resource "google_compute_network" "untrust" {
  name                    = "${local.prefix}untrust"
  auto_create_subnetworks = false
}

// Create trust VPC
resource "google_compute_network" "trust" {
  name                    = "${local.prefix}trust"
  auto_create_subnetworks = false
}

// Create management subnet
resource "google_compute_subnetwork" "mgmt" {
  name          = "${local.prefix}${var.region}-mgmt"
  ip_cidr_range = var.cidr_mgmt
  region        = var.region
  network       = google_compute_network.mgmt.id
}

// Create untrust subnet
resource "google_compute_subnetwork" "untrust" {
  name          = "${local.prefix}${var.region}-untrust"
  ip_cidr_range = var.cidr_untrust
  region        = var.region
  network       = google_compute_network.untrust.id
}

// Create trust subnet
resource "google_compute_subnetwork" "trust" {
  name          = "${local.prefix}${var.region}-trust"
  ip_cidr_range = var.cidr_trust
  region        = var.region
  network       = google_compute_network.trust.id
}

// Firewall rule to allow management access
resource "google_compute_firewall" "mgmt" {
  name          = "${local.prefix}mgmt"
  network       = google_compute_network.mgmt.name
  source_ranges = var.vmseries_mgmt_ips

  allow {
    protocol = "tcp"
    ports    = ["443", "22", "3978"]
  }
}

// Allow all traffic to firewall's untrust VPC
resource "google_compute_firewall" "untrust" {
  name          = "${local.prefix}untrust"
  network       = google_compute_network.untrust.name
  source_ranges = ["0.0.0.0/0"]

  allow {
    protocol = "all"
    ports    = []
  }
}

// Allow all traffic to firewall's trust VPC
resource "google_compute_firewall" "trust" {
  name          = "${local.prefix}trust"
  network       = google_compute_network.trust.name
  source_ranges = ["0.0.0.0/0"]

  allow {
    protocol = "all"
    ports    = []
  }
}


# -------------------------------------------------------------------------------------
#  Create Cloud NAT for untrust VPC.
# -------------------------------------------------------------------------------------

// Create cloud router for cloud NAT.
resource "google_compute_router" "untrust" {
  name    = "${local.prefix}${var.region}untrust-router"
  network = google_compute_network.untrust.id
}

// Create cloud NAT for outbound internet access.
resource "google_compute_router_nat" "untrust" {
  name                               = "${local.prefix}untrust-nat"
  router                             = google_compute_router.untrust.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}


# -------------------------------------------------------------------------------------
# Create bootstrap bucket for VM-Series
# -------------------------------------------------------------------------------------

// Retrieve untrust subnet
data "google_compute_subnetwork" "untrust" {
  self_link = google_compute_subnetwork.untrust.self_link
  region    = var.region
}

// Retrieve trust subnet
data "google_compute_subnetwork" "trust" {
  self_link = google_compute_subnetwork.trust.self_link
  region    = var.region
}

// Create the bootstrap.xml file from bootstrap.template
resource "local_file" "bootstrap" {
  filename = "bootstrap_files/bootstrap.xml"
  content = templatefile("bootstrap_files/bootstrap.template", {
    gateway_trust   = data.google_compute_subnetwork.trust.gateway_address
    gateway_untrust = data.google_compute_subnetwork.untrust.gateway_address
    spoke1_cidr     = var.cidr_spoke1
    spoke2_cidr     = var.cidr_spoke2
    spoke1_vm1_ip   = cidrhost(var.cidr_spoke1, 10)
    spoke2_vm1_ip   = cidrhost(var.cidr_spoke2, 10)
    trust_ip        = google_compute_address.vmseries_trust[0].address // First VM-Series trust interface IP
  })
}


// Create service account for firewall
resource "google_service_account" "vmseries" {
  account_id = "${local.prefix}panw-sa"
}

// Add roles to service account
resource "google_project_iam_member" "vmseries" {
  for_each = var.vmseries_roles
  project  = var.project_id
  role     = each.value
  member   = "serviceAccount:${google_service_account.vmseries.email}"
}

// Create the GCS bootstrap bucket with local firewall config (bootstrap.xml).
module "bootstrap" {
  source          = "PaloAltoNetworks/swfw-modules/google//modules/bootstrap"
  version         = "~> 2.0"
  service_account = google_service_account.vmseries.email
  location        = "US"

  files = {
    "bootstrap_files/init-cfg.txt"     = "config/init-cfg.txt"
    "${local_file.bootstrap.filename}" = "config/bootstrap.xml"
    "bootstrap_files/authcodes"        = "license/authcodes"
  }
}


# -------------------------------------------------------------------------------------
#  Create firewall service account, instance template, MIG, and autoscaler.
# -------------------------------------------------------------------------------------

// Create instance template for the firewall
resource "google_compute_instance_template" "vmseries" {
  name_prefix      = "${local.prefix}panw-template"
  machine_type     = var.vmseries_machine_type
  min_cpu_platform = "Intel Cascade Lake"
  tags             = ["vmseries-tutorial"]
  can_ip_forward   = true

  metadata = {
    type                                 = "dhcp-client"
    dhcp-send-client-id                  = "yes"
    dhcp-accept-server-hostname          = "yes"
    dhcp-accept-server-domain            = "yes"
    dns-primary                          = "169.254.169.254"
    vmseries-bootstrap-gce-storagebucket = module.bootstrap.bucket_name
    ssh-keys                             = "admin:${file(var.public_key_path)}"
  }

  network_interface {
    subnetwork = google_compute_subnetwork.untrust.id
  }

  network_interface {
    subnetwork = google_compute_subnetwork.mgmt.id
    access_config {}
  }

  network_interface {
    subnetwork = google_compute_subnetwork.trust.id
  }

  disk {
    source_image = "https://www.googleapis.com/compute/v1/projects/paloaltonetworksgcp-public/global/images/${var.vmseries_image}"
    disk_type    = "pd-ssd"
    auto_delete  = true
    boot         = true
  }

  lifecycle {
    create_before_destroy = true
  }

  service_account {
    email = google_service_account.vmseries.email
    scopes = [
      "https://www.googleapis.com/auth/compute.readonly",
      "https://www.googleapis.com/auth/cloud.useraccounts.readonly",
      "https://www.googleapis.com/auth/devstorage.read_only",
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring.write",
    ]
  }

  depends_on = [
    module.bootstrap,
    google_compute_router_nat.untrust
  ]
}

# -------------------------------------------------------------------------------------
#  Create static IP addresses for VM-Series instances
#  IP Allocation Strategy for /28 subnets (16 IPs: .0-.15):
#  - Untrust: 10.0.1.10, 10.0.1.11, 10.0.1.12, ... (starting from .10)
#  - Mgmt:    10.0.0.10, 10.0.0.11, 10.0.0.12, ... (starting from .10)
#  - Trust:   10.0.2.2, 10.0.2.3, 10.0.2.4, ... (starting from .2)
#  
#  Trust Subnet Reserved IPs (10.0.2.0/28):
#  - .0 = Network address (reserved)
#  - .1 = Subnet gateway (Google Cloud reserved)
#  - .2-.9 = VM-Series trust interfaces (up to 8 instances)
#  - .10+ = BGP router interfaces (redundant pairs)
#    - VM-Series 1: Primary .10, Backup .11
#    - VM-Series 2: Primary .12, Backup .13
#    - VM-Series 3: Primary .14, Backup .15
#  
#  BGP Configuration (High Availability):
#  - Each VM-Series gets 2 BGP sessions (primary + backup)
#  - Primary interface: Priority 100 (preferred)
#  - Backup interface: Priority 110 (fallback)
#  - Uses router_appliance_instance to link router peers to VM-Series instances
# -------------------------------------------------------------------------------------

// Create static IP addresses for untrust interface
resource "google_compute_address" "vmseries_untrust" {
  count        = var.vmseries_count
  name         = "${local.prefix}panw-vmseries-${count.index + 1}-untrust"
  subnetwork   = google_compute_subnetwork.untrust.id
  address_type = "INTERNAL"
  address      = cidrhost(var.cidr_untrust, 10 + count.index)
  region       = var.region
}

// Create static IP addresses for mgmt interface
resource "google_compute_address" "vmseries_mgmt" {
  count        = var.vmseries_count
  name         = "${local.prefix}panw-vmseries-${count.index + 1}-mgmt"
  subnetwork   = google_compute_subnetwork.mgmt.id
  address_type = "INTERNAL"
  address      = cidrhost(var.cidr_mgmt, 10 + count.index)
  region       = var.region
}

// Create static IP addresses for trust interface
resource "google_compute_address" "vmseries_trust" {
  count        = var.vmseries_count
  name         = "${local.prefix}panw-vmseries-${count.index + 1}-trust"
  subnetwork   = google_compute_subnetwork.trust.id
  address_type = "INTERNAL"
  address      = cidrhost(var.cidr_trust, 2 + count.index)
  region       = var.region
}

# -------------------------------------------------------------------------------------
#  Create VM instances from template and Unmanaged Instance Group (UMIG)
# -------------------------------------------------------------------------------------

// Create VM instance from template
resource "google_compute_instance_from_template" "vmseries" {
  count = var.vmseries_count
  name  = "${local.prefix}panw-vmseries-${count.index + 1}"
  zone  = data.google_compute_zones.available.names[count.index % length(data.google_compute_zones.available.names)]

  source_instance_template = google_compute_instance_template.vmseries.id

  // Override any template settings if needed
  can_ip_forward = true

  // Override network interfaces with static IP addresses
  network_interface {
    subnetwork = google_compute_subnetwork.untrust.id
    network_ip = google_compute_address.vmseries_untrust[count.index].address
  }

  network_interface {
    subnetwork = google_compute_subnetwork.mgmt.id
    network_ip = google_compute_address.vmseries_mgmt[count.index].address
    access_config {
      // Ephemeral public IP
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.trust.id
    network_ip = google_compute_address.vmseries_trust[count.index].address
  }

  // Add labels for identification
  labels = {
    environment = "tutorial"
    role        = "firewall"
    instance    = tostring(count.index + 1)
  }
}

// Get available zones
data "google_compute_zones" "available" {
  region = var.region
}

// Create Unmanaged Instance Groups (one per zone)
resource "google_compute_instance_group" "vmseries" {
  for_each    = toset(data.google_compute_zones.available.names)
  name        = "${local.prefix}panw-umig-${each.key}"
  description = "Unmanaged instance group for VM-Series firewalls in zone ${each.key}"
  zone        = each.key

  instances = [
    for instance in google_compute_instance_from_template.vmseries :
    instance.self_link if instance.zone == each.key
  ]

  named_port {
    name = "http"
    port = "80"
  }

  named_port {
    name = "https"
    port = "443"
  }
} // Note: Autoscaling is not applicable to Unmanaged Instance Groups (UMIG)
// Instances are manually managed through the instance count variable

# -------------------------------------------------------------------------------------
#  Create internal load balancer.
# -------------------------------------------------------------------------------------

// Create health check
resource "google_compute_region_health_check" "vmseries" {
  name = "${local.prefix}panw-hc"
  https_health_check {
    port         = 443
    request_path = "/unauth/php/health.php"
  }
}

# -------------------------------------------------------------------------------------
#  Create external load balancer.
# -------------------------------------------------------------------------------------

// Create forwarding rule for external load balancer.
resource "google_compute_address" "extlb" {
  name         = "${local.prefix}panw-extlb"
  address_type = "EXTERNAL"
}

// Create forwarding rule for external load balancer
resource "google_compute_forwarding_rule" "extlb" {
  name                  = "${local.prefix}panw-extlb"
  project               = var.project_id
  region                = var.region
  load_balancing_scheme = "EXTERNAL"
  all_ports             = true
  ip_protocol           = "TCP"
  ip_address            = google_compute_address.extlb.address
  backend_service       = google_compute_region_backend_service.extlb.self_link
}

// Create backend service.
resource "google_compute_region_backend_service" "extlb" {
  provider              = google-beta
  project               = var.project_id
  region                = var.region
  name                  = "${local.prefix}panw-extlb"
  load_balancing_scheme = "EXTERNAL"
  health_checks         = [google_compute_region_health_check.vmseries.self_link]
  protocol              = "UNSPECIFIED"
  session_affinity      = "CLIENT_IP"

  dynamic "backend" {
    for_each = google_compute_instance_group.vmseries
    content {
      group          = backend.value.self_link
      balancing_mode = "CONNECTION"
    }
  }
}

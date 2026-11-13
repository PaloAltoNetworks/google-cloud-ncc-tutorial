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

// Update bootstrap.template to bootstrap firewall with local config.
data "template_file" "bootstrap" {
  template = file("bootstrap_files/bootstrap.template")
  vars = {
    gateway_trust   = data.google_compute_subnetwork.trust.gateway_address
    gateway_untrust = data.google_compute_subnetwork.untrust.gateway_address
    spoke1_cidr     = var.cidr_spoke1
    spoke2_cidr     = var.cidr_spoke2
    spoke1_vm1_ip   = cidrhost(var.cidr_spoke1, 10)
    spoke2_vm1_ip   = cidrhost(var.cidr_spoke2, 10)
  }
}


// Create the bootstrap.xml file from bootstrap.template
resource "local_file" "bootstrap" {
  filename = "bootstrap_files/bootstrap.xml"
  content  = data.template_file.bootstrap.rendered
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
    dynamic "access_config" {
      for_each = var.mgmt_public_ip ? [1] : []
      content {}
    }
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


// Create regional instance group
resource "google_compute_region_instance_group_manager" "vmseries" {
  name                      = "${local.prefix}panw-mig"
  base_instance_name        = "${local.prefix}panw-firewall"
  distribution_policy_zones = data.google_compute_zones.main.names

  version {
    instance_template = google_compute_instance_template.vmseries.id
  }
}


// Configure autoscaling policy for instance group
resource "google_compute_region_autoscaler" "vmseries" {
  name   = "${local.prefix}panw-autoscaler"
  target = google_compute_region_instance_group_manager.vmseries.id

  autoscaling_policy {
    min_replicas    = var.vmseries_scale_min
    max_replicas    = var.vmseries_scale_max
    cooldown_period = 480
  }
}


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

// Create forwarding rule for internal load balancer
resource "google_compute_forwarding_rule" "intlb" {
  name                  = "${local.prefix}panw-intlb"
  project               = var.project_id
  region                = var.region
  load_balancing_scheme = "INTERNAL"
  all_ports             = true
  ip_protocol           = "UDP"
  allow_global_access   = true
  backend_service       = google_compute_region_backend_service.intlb.self_link
  subnetwork            = google_compute_subnetwork.trust.id
  ip_address            = cidrhost(var.cidr_trust, 10) # Directly assign without reserving
}

// Create backend service.
resource "google_compute_region_backend_service" "intlb" {
  name          = "${local.prefix}panw-lb"
  protocol      = "UDP"
  network       = google_compute_network.trust.id
  health_checks = [google_compute_region_health_check.vmseries.self_link]

  backend {
    group          = google_compute_region_instance_group_manager.vmseries.instance_group
    balancing_mode = "CONNECTION"
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

  backend {
    group          = google_compute_region_instance_group_manager.vmseries.instance_group
    balancing_mode = "CONNECTION"
  }
}

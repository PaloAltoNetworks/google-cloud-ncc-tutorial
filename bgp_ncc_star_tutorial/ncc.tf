# -------------------------------------------------------------------------------------
#  Create NCC hub with edge and center groups for the trust VPC network.
# -------------------------------------------------------------------------------------

// Create NCC hub in star topology
resource "google_network_connectivity_hub" "main" {
  count           = (var.configure_ncc ? 1 : 0)
  name            = "${local.prefix}panw-hub"
  preset_topology = "STAR"
}

// Create NCC center group for VM-Series
resource "google_network_connectivity_group" "center" {
  count = (var.configure_ncc ? 1 : 0)
  hub   = google_network_connectivity_hub.main[0].id
  name  = "center"
  auto_accept {
    auto_accept_projects = [
      var.project_id
    ]
  }
}

// Create NCC edge group for VM-Series
resource "google_network_connectivity_group" "edge" {
  count = (var.configure_ncc ? 1 : 0)
  hub   = google_network_connectivity_hub.main[0].id
  name  = "edge"
  auto_accept {
    auto_accept_projects = [
      var.project_id
    ]
  }
}

module "trust_router" {
  count   = (var.configure_ncc ? 1 : 0)
  source  = "terraform-google-modules/cloud-router/google"
  version = "~> 7.1"
  name    = "cr-trust"
  region  = var.region
  bgp = {
    asn               = 65000
    advertised_groups = ["ALL_SUBNETS"]
  }
  project = var.project_id
  network = google_compute_network.trust.name
}

// Create primary BGP interfaces on the cloud router
resource "google_compute_router_interface" "trust_nic0" {
  count               = (var.configure_ncc ? var.vmseries_count : 0)
  name                = "trust-to-ncc-${count.index + 1}-primary"
  router              = module.trust_router[0].router.name
  region              = module.trust_router[0].router.region
  subnetwork          = google_compute_subnetwork.trust.self_link
  private_ip_address  = cidrhost(var.cidr_trust, 10 + (count.index * 2))
  redundant_interface = google_compute_router_interface.trust_nic1[count.index].name
}

// Create backup BGP interfaces on the cloud router
resource "google_compute_router_interface" "trust_nic1" {
  count              = (var.configure_ncc ? var.vmseries_count : 0)
  name               = "trust-to-ncc-${count.index + 1}-backup"
  router             = module.trust_router[0].router.name
  region             = module.trust_router[0].router.region
  subnetwork         = google_compute_subnetwork.trust.self_link
  private_ip_address = cidrhost(var.cidr_trust, 11 + (count.index * 2))
}

// Create primary BGP peers using the primary cloud router interface
resource "google_compute_router_peer" "trust_primary" {
  count                     = (var.configure_ncc ? var.vmseries_count : 0)
  name                      = "trust-peer-${count.index + 1}-primary"
  router                    = module.trust_router[0].router.name
  region                    = var.region
  peer_asn                  = 65001
  router_appliance_instance = google_compute_instance_from_template.vmseries[count.index].id
  peer_ip_address           = google_compute_address.vmseries_trust[count.index].address
  interface                 = google_compute_router_interface.trust_nic0[count.index].name
  advertised_route_priority = 100

  depends_on = [
    google_compute_instance_from_template.vmseries,
    google_compute_address.vmseries_trust,
    google_compute_router_interface.trust_nic0,
    google_network_connectivity_spoke.trust
  ]
}

// Create backup BGP peers using the backup cloud router interface
resource "google_compute_router_peer" "trust_backup" {
  count                     = (var.configure_ncc ? var.vmseries_count : 0)
  name                      = "trust-peer-${count.index + 1}-backup"
  router                    = module.trust_router[0].router.name
  region                    = var.region
  peer_asn                  = 65001
  router_appliance_instance = google_compute_instance_from_template.vmseries[count.index].id
  peer_ip_address           = google_compute_address.vmseries_trust[count.index].address
  interface                 = google_compute_router_interface.trust_nic1[count.index].name
  advertised_route_priority = 110

  depends_on = [
    google_compute_instance_from_template.vmseries,
    google_compute_address.vmseries_trust,
    google_compute_router_interface.trust_nic1,
    google_network_connectivity_spoke.trust
  ]
} // Create NCC spoke for trust VPC with router appliance instances
resource "google_network_connectivity_spoke" "trust" {
  count    = (var.configure_ncc ? 1 : 0)
  name     = "${local.prefix}trust"
  location = var.region
  group    = google_network_connectivity_group.center[0].id
  hub      = google_network_connectivity_hub.main[0].id

  linked_router_appliance_instances {
    dynamic "instances" {
      for_each = range(var.vmseries_count)
      content {
        virtual_machine = google_compute_instance_from_template.vmseries[instances.value].id
        ip_address      = google_compute_address.vmseries_trust[instances.value].address
      }
    }
    site_to_site_data_transfer = true
  }
}

// Create NCC spoke for spoke1-vpc
resource "google_network_connectivity_spoke" "spoke1" {
  count    = (var.configure_ncc ? 1 : 0)
  name     = "${local.prefix}spoke1"
  location = "global"
  group    = google_network_connectivity_group.edge[0].id
  hub      = google_network_connectivity_hub.main[0].id

  linked_vpc_network {
    uri = google_compute_network.spoke1.self_link
  }
}

// Create NCC spoke for spoke2-vpc
resource "google_network_connectivity_spoke" "spoke2" {
  count    = (var.configure_ncc ? 1 : 0)
  name     = "${local.prefix}spoke2"
  location = "global"
  group    = google_network_connectivity_group.edge[0].id
  hub      = google_network_connectivity_hub.main[0].id

  linked_vpc_network {
    uri = google_compute_network.spoke2.self_link
  }
}



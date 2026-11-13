output "EXTERNAL_LB_IP" {
  value = google_compute_address.extlb.address
}

output "VMSERIES_UNTRUST_IPS" {
  description = "Static internal IP addresses for VM-Series untrust interfaces"
  value = {
    for i, addr in google_compute_address.vmseries_untrust :
    "vmseries-${i + 1}" => addr.address
  }
}

output "VMSERIES_MGMT_IPS" {
  description = "Static internal IP addresses for VM-Series management interfaces"
  value = {
    for i, addr in google_compute_address.vmseries_mgmt :
    "vmseries-${i + 1}" => addr.address
  }
}

output "VMSERIES_TRUST_IPS" {
  description = "Static internal IP addresses for VM-Series trust interfaces"
  value = {
    for i, addr in google_compute_address.vmseries_trust :
    "vmseries-${i + 1}" => addr.address
  }
}

output "IP_ALLOCATION_SUMMARY" {
  description = "Complete IP allocation summary to avoid conflicts"
  value = {
    "subnet_gateways" = {
      "untrust" = cidrhost(var.cidr_untrust, 1)
      "mgmt"    = cidrhost(var.cidr_mgmt, 1)
      "trust"   = cidrhost(var.cidr_trust, 1)
    }
    "bgp_configuration" = {
      "router_interfaces_primary" = {
        for i in range(var.vmseries_count) :
        "interface-${i + 1}-primary" => cidrhost(var.cidr_trust, 10 + (i * 2))
      }
      "router_interfaces_backup" = {
        for i in range(var.vmseries_count) :
        "interface-${i + 1}-backup" => cidrhost(var.cidr_trust, 11 + (i * 2))
      }
      "vmseries_trust_ips" = {
        for i in range(var.vmseries_count) :
        "vmseries-${i + 1}" => cidrhost(var.cidr_trust, 2 + i)
      }
      "bgp_peers" = {
        for i in range(var.vmseries_count) :
        "vmseries-${i + 1}" => {
          "primary" = "Router ${cidrhost(var.cidr_trust, 10 + (i * 2))} <-> VM-Series ${cidrhost(var.cidr_trust, 2 + i)} (Priority 100)"
          "backup"  = "Router ${cidrhost(var.cidr_trust, 11 + (i * 2))} <-> VM-Series ${cidrhost(var.cidr_trust, 2 + i)} (Priority 110)"
        }
      }
    }
    "vmseries_ip_ranges" = {
      "untrust_start" = cidrhost(var.cidr_untrust, 10)
      "untrust_end"   = cidrhost(var.cidr_untrust, 9 + var.vmseries_count)
      "mgmt_start"    = cidrhost(var.cidr_mgmt, 10)
      "mgmt_end"      = cidrhost(var.cidr_mgmt, 9 + var.vmseries_count)
      "trust_start"   = cidrhost(var.cidr_trust, 10)
      "trust_end"     = cidrhost(var.cidr_trust, 9 + var.vmseries_count)
    }
    "available_ranges" = {
      "untrust_available" = "${cidrhost(var.cidr_untrust, 2)} - ${cidrhost(var.cidr_untrust, 9)}"
      "mgmt_available"    = "${cidrhost(var.cidr_mgmt, 2)} - ${cidrhost(var.cidr_mgmt, 9)}"
      "trust_available"   = "${cidrhost(var.cidr_trust, 2)} - ${cidrhost(var.cidr_trust, 9)}"
    }
  }
}

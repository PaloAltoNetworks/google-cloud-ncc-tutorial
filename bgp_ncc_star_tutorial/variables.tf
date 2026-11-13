# -------------------------------------------------------------------------------------
# Required variables
# -------------------------------------------------------------------------------------

variable "project_id" {
  type        = string
  description = "GCP Project ID for the deployment."
}

variable "region" {
  type        = string
  description = "GCP region for the deployment."
}

variable "public_key_path" {
  type        = string
  description = "Local path to public SSH key. To generate the key pair use `ssh-keygen -t rsa -C admin -N '' -f id_rsa`  If you do not have a public key, run `ssh-keygen -f ~/.ssh/demo-key -t rsa -C admin`"
}

variable "vmseries_mgmt_ips" {
  type        = list(string)
  description = "A list of IP addresses to be added to the management network's ingress firewall rule. The IP addresses will be able to access to the VM-Series management interface."
}

variable "configure_ncc" {
  type        = bool
  description = "If set to true, ncc.tf will be executed and the NCC hub, groups, and spokes will be created automatically."
}


# -------------------------------------------------------------------------------------
# Optional variables
# ------------------------------------------------------------------------------------

variable "prefix" {
  type        = string
  description = "Prefix to add to GCP resource names, an arbitrary string"
  default     = null
}

variable "cidr_mgmt" {
  type        = string
  description = "The CIDR range of the management subnetwork."
  default     = "10.0.0.0/24"
}

variable "cidr_untrust" {
  type        = string
  description = "The CIDR range of the untrust subnetwork."
  default     = "10.0.1.0/24"
}

variable "cidr_trust" {
  type        = string
  description = "The CIDR range of the trust subnetwork."
  default     = "10.0.2.0/24"
}

variable "cidr_spoke1" {
  type        = string
  description = "The CIDR range of the spoke1 subnetwork."
  default     = "10.1.0.0/24"
}

variable "cidr_spoke2" {
  type        = string
  description = "The CIDR range of the spoke2 subnetwork."
  default     = "10.2.0.0/24"
}

variable "vmseries_image" {
  type        = string
  description = "Name of the VM-Series image within the paloaltonetworksgcp-public project.  To list available images, run: `gcloud compute images list --project paloaltonetworksgcp-public --no-standard-images`. If you are using a custom image in a different project, please update `local.vmseries_iamge_url` in `main.tf`."
  default     = "vmseries-flex-bundle2-1022h2"
}

variable "vmseries_machine_type" {
  type        = string
  description = "The machine shape for the VM-Series instance (N2 and E2 instances are supported)."
  default     = "n2-standard-4"
}

variable "vmseries_count" {
  type        = string
  description = "The minimum number of firewalls to scale up to during scaling event."
  default     = 1
}

variable "vmseries_roles" {
  type        = set(string)
  description = "Roles to assign to the firewall's service account."
  default = [
    "roles/compute.networkViewer",
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer",
    "roles/viewer",
    "roles/stackdriver.accounts.viewer",
    "roles/stackdriver.resourceMetadata.writer",
  ]
}


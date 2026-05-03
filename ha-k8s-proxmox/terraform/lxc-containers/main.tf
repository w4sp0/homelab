terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.104.0"
    }
  }
}

# ---------------------------------------------------------------------------
# Provider authentication
#
# Option A - API token (recommended, least privilege)
#   Run: ./scripts/setup-proxmox-token.sh <proxmox-ip>
#
# Option B - root@pam (simpler, full admin access)
#   Replace api_token with: username = "root@pam" / password = var.proxmox_password
# ---------------------------------------------------------------------------
provider "proxmox" {
  endpoint  = "https://100.111.118.45:8006"
  api_token = var.proxmox_api_token
  insecure  = true # set false if your Proxmox node has a valid TLS certificate
}

# ---------------------------------------------------------------------------
# All containers are defined in containers.yaml file.
# To add a new container: edit containers.yaml, run terraform apply
# No HCL changes required.
# ---------------------------------------------------------------------------

locals {
  containers = yamldecode(file("${path.module}/containers.yaml"))
}

# ---------------------------------------------------------------------------
# Download the LXC template once.
# This takes several minutes on first apply (~200 MB tarball).
# Proxmox skips the download on subsequent applies if the file already exists.
# ---------------------------------------------------------------------------
resource "proxmox_virtual_environment_download_file" "template" {
  node_name           = var.pm_node
  content_type        = "vztmpl"
  datastore_id        = var.template_datastore_id
  url                 = var.template_url
  overwrite_unmanaged = true
}

# ---------------------------------------------------------------------------
# Create a single LXC container using the module.
# All values come from terraform.tfvars — no edits to this file needed.
# ---------------------------------------------------------------------------
module "containers" {
  for_each = local.containers
  source = "../.."

  node_name        = var.pm_node
  template_file_id = proxmox_virtual_environment_download_file.template.id
  proxmox_ssh_host = var.proxmox_host

  # per-container identity (required for containers.yaml)
  vm_id            = var.vmid
  hostname         = each.key

  # Resource sizing per-container override
  cpu_cores = lookup(each.value, "cpu_cores", 1)
  memory    = lookup(each.value, "memory", 1)
  disk_size = lookup(each.value, "disk_size", 1)
  storage   = lookup(each.value, "storage", 1)

  # Network - per-container override or module default
  ip_address  = each.value.ip_address
  gateway     = lookup(each.value, "gateway", var.gateway)
  dns_servers = lookup(each.value, "dns_servers", var.dns_servers)
  bridge      = lookup(each.value, "bridge", var.bridge)
  vlan_tag    = lookup(each.value, "vlan_tag", var.vlan_tag)

  # Container behaviour - per-container override or module default
  os_type       = lookup(each.value, "os_type", "fedora")
  unprivileged  = lookup(each.value, "unprivileged", true)
  nesting       = lookup(each.value, "nesting", true)
  start_on_boot = lookup(each.value, "start_on_boot", true)
  started       = lookup(each.value, "started", true)
  pool_id       = lookup(each.value, "pool_id", "")
  protection    = lookup(each.value, "protection", false)

  # Advanced
  mount_features = lookup(each.value, "mount_features", [])
  mount_points   = lookup(each.value, "mount_points", [])

  # Metadata
  tags        = lookup(each.value, "tags", [])
  description = lookup(each.value, "description", "")

  ssh_public_keys = [var.ssh_public_key]
}

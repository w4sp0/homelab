locals {
  pm_nodes = toset(distinct(concat(
    [for c in var.talos_control_configuration : c.pm_node],
    [for w in var.talos_worker_configuration : w.pm_node],
  )))
}

resource "proxmox_virtual_environment_download_file" "talos_iso" {
  for_each = local.pm_nodes

  content_type        = "iso"
  datastore_id        = "local"
  file_name           = "metal-amd64.iso"
  node_name           = each.value
  url                 = var.talos_iso_url
  overwrite_unmanaged = true
}

resource "proxmox_virtual_environment_vm" "talos_control" {
  for_each = { for config in var.talos_control_configuration : config.vmid => config }
  name        = each.value.vm_name
  description = "Talos control plane node"
  tags        = ["control", "kubernetes"]

  node_name = each.value.pm_node
  vm_id     = each.value.vmid

  agent {
    # read 'Qemu guest agent' section, change to true only when ready
    enabled = false
  }
  # if agent is not enabled, the VM may not be able to shutdown properly, and may need to be forced off
  stop_on_destroy = true

  boot_order = ["scsi0", "ide2"]

  startup {
    order      = "3"
    up_delay   = "60"
    down_delay = "60"
  }

  cpu {
    cores = each.value.cpu_cores
    type  = "x86-64-v2-AES"  # recommended for modern CPUs
  }

  memory {
    dedicated = each.value.memory
    floating  = each.value.memory # set equal to dedicated to enable ballooning
  }

  disk {
    datastore_id = "local-lvm"
    interface    = "scsi0"
    size         = each.value.disk_size
  }

  cdrom {
    interface = "ide2"
    file_id   = proxmox_virtual_environment_download_file.talos_iso[each.value.pm_node].id
  }

  network_device {
    bridge      = "vmbr0"
    mac_address = each.value.networks[0].macaddr
  }

  operating_system {
    type = "l26"
  }

  serial_device {}
}

resource "proxmox_virtual_environment_vm" "talos_worker" {
  for_each = { for config in var.talos_worker_configuration : config.vmid => config }
  name        = each.value.vm_name
  description = "Talos worker plane node"
  tags        = ["worker", "kubernetes"]

  node_name = each.value.pm_node
  vm_id     = each.value.vmid

  agent {
    # read 'Qemu guest agent' section, change to true only when ready
    enabled = false
  }
  # if agent is not enabled, the VM may not be able to shutdown properly, and may need to be forced off
  stop_on_destroy = true

  boot_order = ["scsi0", "ide2"]

  startup {
    order      = "3"
    up_delay   = "60"
    down_delay = "60"
  }

  cpu {
    cores = each.value.cpu_cores
    type  = "x86-64-v2-AES"  # recommended for modern CPUs
  }

  memory {
    dedicated = each.value.memory
    floating  = each.value.memory # set equal to dedicated to enable ballooning
  }

  disk {
    datastore_id = "local-lvm"
    interface    = "scsi0"
    size         = each.value.disk_size
  }

  cdrom {
    interface = "ide2"
    file_id   = proxmox_virtual_environment_download_file.talos_iso[each.value.pm_node].id
  }

  network_device {
    bridge      = "vmbr0"
    mac_address = each.value.networks[0].macaddr
  }

  operating_system {
    type = "l26"
  }

  serial_device {}
}

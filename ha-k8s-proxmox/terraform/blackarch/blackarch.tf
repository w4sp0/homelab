resource "proxmox_download_file" "blackarch_iso" {
  content_type          = "iso"
  datastore_id          = "local"
  file_name             = "blackarch-linux-full-2023.04.01-x86_64.iso"
  node_name             = var.pm_node
  url                   = var.blackarch_iso_url
  overwrite_unmanaged   = true
  upload_timeout        = 3600
}

resource "proxmox_virtual_environment_vm" "blackarch_full" {
  name = var.vm_name
  description = "BlackArch full distro - pentesting"
  tags = ["security", "pentest", "dev"]

  node_name = var.pm_node
  vm_id = var.vmid

  agent {
    enabled = false
  }
  stop_on_destroy = true

  boot_order = ["scsi0", "ide2"]

  startup {
    order      = "3"
    up_delay   = "60"
    down_delay = "60"
  }

  cpu {
    cores = var.cpu_cores
    type  = "x86-64-v2-AES"
  }

  memory {
    floating  = var.memory
    dedicated = var.memory
  }

  disk {
    datastore_id = "local-lvm"
    interface    = "scsi0"
    size         = var.disk_size
  }

  cdrom  {
    interface = "ide2"
    file_id   = proxmox_download_file.blackarch_iso.id
  }

  network_device {
    bridge = "vmbr0"
    mac_address = var.networks[0].macaddr
  }

  operating_system {
    type = "l26"
  }

  serial_device {}
}

terraform {
  required_providers {
    proxmox = {
      source  = "Telmate/proxmox"
      version = "3.0.2-rc07"
    }
  }
}

provider "proxmox" {
  pm_api_url          = var.pm_api_url
  pm_user             = var.pm_username
  pm_api_token_id     = var.pm_api_token_id
  pm_api_token_secret = var.pm_api_token_secret
  pm_tls_insecure     = true
}

resource "proxmox_vm_qemu" "security_remnux" {
  target_node        = var.remnux_config.pm_node
  vmid               = var.remnux_config.vmid
  name               = var.remnux_config.vm_name
  description        = "REMnux malware analysis VM"
  agent              = 1
  full_clone         = false
  define_connection_info = false
  start_at_node_boot = true
  vm_state           = "running"

  memory = var.remnux_config.memory
  cpu {
    cores   = var.remnux_config.cpu_cores
    sockets = 1
    type    = "host"
  }

  ipconfig0 = "ip=dhcp"
  skip_ipv6 = true

  network {
    id     = 0
    model  = "virtio"
    bridge = "vmbr0"
  }

  scsihw = "virtio-scsi-single"
  boot   = "order=scsi0"

  disks {
    scsi {
      scsi0 {
        disk {
          storage = "local-lvm"
          size    = var.remnux_config.disk_size
        }
      }
    }
  }

  vga {
    type = "qxl"
  }

  lifecycle {
    ignore_changes = [disk, vm_state, network, target_nodes]
  }

  tags = "security,remnux"
}

resource "proxmox_vm_qemu" "security_blackarch" {
  target_node           = var.blackarch_config.pm_node
  vmid                  = var.blackarch_config.vmid
  name                  = var.blackarch_config.vm_name
  clone                 = "blackarch-template"
  description           = "BlackArch penetration testing VM"
  agent                 = 1
  full_clone            = true
  define_connection_info = false
  start_at_node_boot    = true
  vm_state              = "running"

  memory = var.blackarch_config.memory
  cpu {
    cores   = var.blackarch_config.cpu_cores
    sockets = 1
    type    = "host"
  }

  ipconfig0 = "ip=dhcp"
  skip_ipv6 = true

  network {
    id     = 0
    model  = "virtio"
    bridge = "vmbr0"
  }

  scsihw = "virtio-scsi-single"
  boot   = "order=scsi0"

  disks {
    scsi {
      scsi0 {
        disk {
          storage = "local-lvm"
          size    = var.blackarch_config.disk_size
        }
      }
    }
  }

  vga {
    type = "qxl"
  }

  lifecycle {
    ignore_changes = [disk, vm_state, network, target_nodes]
  }

  tags = "security,blackarch"
}

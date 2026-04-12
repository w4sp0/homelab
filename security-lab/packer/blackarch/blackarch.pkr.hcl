packer {
  required_plugins {
    proxmox = {
      version = ">= 1.2.2"
      source  = "github.com/hashicorp/proxmox"
    }
  }
}

source "proxmox-iso" "blackarch" {
  # Proxmox connection
  proxmox_url              = var.proxmox_url
  username                 = var.proxmox_username
  token                    = var.proxmox_token
  insecure_skip_tls_verify = true
  node                     = var.proxmox_node

  # VM settings
  vm_id                = var.vmid
  vm_name              = "blackarch-template"
  template_description = "BlackArch slim - Kubernetes/cloud pentesting"
  qemu_agent           = true

  # ISO
  iso_file = "local:iso/blackarch-linux-slim-2023.05.01-x86_64.iso"

  # System
  cores    = 2
  sockets  = 1
  cpu_type = "host"
  memory   = 4096

  # Storage
  scsi_controller = "virtio-scsi-single"

  disks {
    type         = "scsi"
    storage_pool = "local-lvm"
    disk_size    = "50G"
    format       = "raw"
  }

  # Network
  network_adapters {
    model  = "virtio"
    bridge = "vmbr0"
  }

  # Display
  vga {
    type = "qxl"
  }

  # Boot - wait for live env, set root password, start sshd
  boot      = "order=scsi0;ide2"
  boot_wait = "60s"

  boot_command = [
    "<enter><wait30>",
    "root<enter><wait5>",
    "passwd<enter><wait2>",
    "packer<enter><wait2>",
    "packer<enter><wait2>",
    "systemctl start sshd<enter><wait5>",
  ]

  # SSH communicator
  ssh_username = "root"
  ssh_password = "packer"
  ssh_timeout  = "15m"
}

build {
  sources = ["source.proxmox-iso.blackarch"]

  provisioner "shell" {
    script = "scripts/install.sh"
    environment_vars = [
      "DISK=/dev/sda",
    ]
  }

  provisioner "shell" {
    script = "scripts/setup.sh"
    pause_before = "5s"
  }
}

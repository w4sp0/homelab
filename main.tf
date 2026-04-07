resource "proxmox_vm_qemu" "talos_control" {
  for_each = { for index, config in var.talos_control_configuration : config.vmid => config }
  
  target_node = each.value.pm_node
  vmid = each.value.vmid
  name = each.value.name
  description = "Talos control plane node ${each.value.vmid}"
  agent = 1
  onboot = true
  vm_state = "running"

  memory = each.value.memory
  cpu {
    cores = each.value.cpu_cores
    sockets = 1
    type = "host"
  }

  ipconfig0 = "ip=dhcp"
  skip_ipv6 = true

  dynamic "network" {
    for_each = each.value.networks
    content {
      id = network.value.id
      model = "virtio"
      bridge = "vmbr0"
      macaddr = network.value.macaddr
      tag = network.value.tag
    }
  }

  scsihw = "virtio-scsi-single"  
  boot = "order=scsi0;ide2"  
  disks {
    scsi {
      scsi0 {
        disk {
          storage = "local-lvm"
          size = each.value.disk_size
        }
      }
    }
    ide {
      ide2 {
        cdrom {
          iso = var.talos_iso_file
        }
      }
    }
  }

  lifecycle {
    ignore_changes = [disk, vm_state]
  

  tags = "kubernetes,control"
}

resource "proxmox_vm_qemu" "talos_worker" 

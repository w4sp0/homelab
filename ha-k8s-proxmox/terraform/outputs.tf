output "control_plane_ips" {
  description = "IP addresses of Talos control plane nodes"
  value = {
    for vmid, vm in proxmox_vm_qemu.talos_control :
    vm.name => vm.default_ipv4_address
  }
}

output "worker_ips" {
  description = "IP addresses of Talos worker nodes"
  value = {
    for vmid, vm in proxmox_vm_qemu.talos_worker :
    vm.name => vm.default_ipv4_address
  }
}

output "control_plane_vmids" {
  description = "VMIDs of control plane nodes"
  value = {
    for vmid, vm in proxmox_vm_qemu.talos_control :
    vm.name => vm.vmid
  }
}

output "worker_vmids" {
  description = "VMIDs of worker nodes"
  value = {
    for vmid, vm in proxmox_vm_qemu.talos_worker :
    vm.name => vm.vmid
  }
}

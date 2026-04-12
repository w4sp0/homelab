output "remnux_ip" {
  description = "IP address of the REMnux VM"
  value       = proxmox_vm_qemu.security_remnux.default_ipv4_address
}

output "remnux_vmid" {
  description = "VMID of the REMnux VM"
  value       = proxmox_vm_qemu.security_remnux.vmid
}

output "blackarch_ip" {
  description = "IP address of the BlackArch VM"
  value       = proxmox_vm_qemu.security_blackarch.default_ipv4_address
}

output "blackarch_vmid" {
  description = "VMID of the BlackArch VM"
  value       = proxmox_vm_qemu.security_blackarch.vmid
}

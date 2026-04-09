output "remnux_ip" {
  description = "IP address of the REMnux VM"
  value       = proxmox_vm_qemu.security_remnux.default_ipv4_address
}

output "remnux_vmid" {
  description = "VMID of the REMnux VM"
  value       = proxmox_vm_qemu.security_remnux.vmid
}

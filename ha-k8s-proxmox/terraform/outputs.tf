output "control_plane_vmids" {
  description = "VMIDs of controlplane nodes"
  value       = { for vmid, vm in proxmox_virtual_environment_vm.talos_control : vm.name => vm.vm_id }
}

output "worker_vmids" {
  description = "VMIDs of worker nodes"
  value       = { for vmid, vm in proxmox_virtual_environment_vm.talos_worker : vm.name => vm.vm_id }
}

output "kubeconfig" {
  description = "Kubeconfig for the cluster"
  value = data.talos_cluster_kubeconfig.kubeconfig.kubeconfig_raw
  sensitive = true
}

output "talosconfig" {
  description = "talosctl client configuration"
  value = talos_machine_secrets.cluster.client_configuration
  sensitive = true
}

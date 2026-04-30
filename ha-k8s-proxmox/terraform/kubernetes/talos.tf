resource "talos_machine_secrets" "cluster" {}

data "talos_machine_configuration" "control" {
  cluster_name       = var.cluster_name
  cluster_endpoint   = "https://${var.cluster_vip}:6443"
  machine_type       = "controlplane"
  machine_secrets    = talos_machine_secrets.cluster.machine_secrets
  config_patches     = [file("${path.module}/../talos/patches/controlplane.yaml")]
}

data "talos_machine_configuration" "worker" {
  cluster_name     = var.cluster_name
  cluster_endpoint = "https://${var.cluster_vip}:6443"
  machine_type     = "worker"
  machine_secrets  = talos_machine_secrets.cluster.machine_secrets
  config_patches   = []
}

resource "talos_machine_configuration_apply" "control" {
  for_each = { for c in var.talos_control_configuration : c.vmid => c }

  depends_on                  = [proxmox_virtual_environment_vm.talos_control]
  client_configuration        = talos_machine_secrets.cluster.client_configuration
  machine_configuration_input = data.talos_machine_configuration.control.machine_configuration
  node                        = each.value.ip_address
}

resource "talos_machine_configuration_apply" "worker" {
  for_each = { for c in var.talos_worker_configuration : c.vmid => c }

  depends_on                  = [proxmox_virtual_environment_vm.talos_worker]
  client_configuration        = talos_machine_secrets.cluster.client_configuration
  machine_configuration_input = data.talos_machine_configuration.worker.machine_configuration
  node                        = each.value.ip_address
}

resource "talos_machine_bootstrap" "bootstrap" {
  depends_on           = [talos_machine_configuration_apply.control]
  client_configuration = talos_machine_secrets.cluster.client_configuration
  node                 = var.bootstrap_node_ip
}

data "talos_cluster_kubeconfig" "kubeconfig" {
  depends_on           = [talos_machine_bootstrap.bootstrap]
  client_configuration = talos_machine_secrets.cluster.client_configuration
  node                 = var.bootstrap_node_ip
}

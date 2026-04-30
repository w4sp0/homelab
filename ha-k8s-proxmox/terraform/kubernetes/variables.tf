variable "pm_api_token" {
  type = string
  sensitive = true
}

variable "talos_iso_url" {
  type = string
}

variable "cluster_name" {
  type        = string
  description = "Cluster name, e.g. homelab"
}

variable "cluster_vip" {
  type        = string
  description = "Cluster API VIP"
}

variable "bootstrap_node_ip" {
  type        = string
  description = "IP of the first control plane"
}


variable "talos_control_configuration" {
  type = list(object({
    pm_node      = string
    vmid         = number
    vm_name      = string
    cpu_cores    = number
    memory       = number
    disk_size    = number
    ip_address   = string
    networks     = list(object({
      id         = number
      macaddr    = string
      tag        = optional(number, 0)
    }))
  }))
}

variable "talos_worker_configuration" {
  type = list(object({
    pm_node      = string
    vmid         = number
    vm_name      = string
    cpu_cores    = number
    memory       = number
    disk_size    = number
    ip_address   = string
    networks     = list(object({
      id         = number
      macaddr    = string
      tag        = optional(number)
    }))
  }))
  default = []
}

variable "pm_api_url" {
  type        = string
  description = "Proxmox API URL, e.g. https://pve1.lan:8006/api2/json"
}

variable "pm_username" {
  type        = string
  description = "Proxmox user, e.g. root@pam"
}

variable "pm_api_token_id" {
  type        = string
  description = "API token ID, e.g. root@pam!terraform"
}

variable "pm_api_token_secret" {
  type        = string
  sensitive   = true
  description = "API token secret UUID"
}

variable "talos_iso_file" {
  type        = string
  description = "Proxmox ISO path, e.g. local:iso/metal-amd64.iso"
}

variable "talos_control_configuration" {
  type = list(object({
    pm_node   = string
    vmid      = number
    vm_name   = string
    cpu_cores = number
    memory    = number
    disk_size = string
    networks  = list(object({
      id      = number
      macaddr = string
      tag     = optional(number, 0)
    }))
  }))
}

variable "talos_worker_configuration" {
  type = list(object({
    pm_node   = string
    vmid      = number
    vm_name   = string
    cpu_cores = number
    memory    = number
    disk_size = string
    networks  = list(object({
      id      = number
      macaddr = string
      tag     = optional(number)
    }))
  }))
  default = []
}

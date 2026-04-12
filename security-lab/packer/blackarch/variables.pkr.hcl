variable "proxmox_url" {
  type        = string
  description = "Proxmox API URL, e.g. https://pve1.lan:8006/api2/json"
}

variable "proxmox_username" {
  type        = string
  description = "Proxmox API token user, e.g. root@pam!terraform"
}

variable "proxmox_token" {
  type        = string
  sensitive   = true
  description = "Proxmox API token secret"
}

variable "proxmox_node" {
  type        = string
  default     = "pve0-nic0"
  description = "Target Proxmox node"
}

variable "vmid" {
  type        = number
  default     = 9002
  description = "VM ID for the template (use 9xxx range for templates)"
}

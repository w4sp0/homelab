variable "pm_api_token" {
  type      = string
  sensitive = true
}

variable "pm_node" {
  type = string
  description = "Node onto which to deploy the VM"
}

variable "template_url" {
  type = string
  description = "URL to download the template iso from"
  default = "http://download.proxmox.com/images/system/fedora-43-default_20260115_amd64.tar.xz"
}

variable "template_datastore_id" {
  type        = string
  description = "Datastore where the LXC template lives. Must support 'vztmpl' content type."
  default     = "local"
}

variable "proxmox_host" {
  type = string
  description = "IP or hostname of the Proxmox node"
}

variable "vmid" {
  type = number
}

variable "vm_name" {
  type = string
}

variable "cpu_cores" {
  type        = number
  description = "Number of cores allocated to the VM"
}

variable "memory" {
  type        = number
  description = "Amount of memory allocated to the VM"
}


variable "storage" {
  type        = string
  description = "Datastore for the container root disk"
  default     = "local-lvm"
}

variable "disk_size" {
  type        = number
  description = "Amount of disk memory allocated to the VM"
}

variable "ip_address" {
  type        = string
  description = "IP address of the VM"
}

variable "dns_servers" {
  type        = string
  description = "IP address of the VM"
}

variable "bridge" {
  type        = string
  description = "IP address of the VM"
  default     = "vmbr0"
}

variable "vlan_tag" {
  type        = string
  description = "Default VLAN tag for all containers. Set to 0 to disable (can be overridden per container in containers.yaml)."
  default     = 0
}

variable "networks" {
  type = list(object({
      id      = number
      macaddr = string
      tag     = optional(number, 0)
  }))
}

variable "pm_api_token" {
  type      = string
  sensitive = true
}

variable "blackarch_iso_url" {
  type = string
  description = "URL to download the blackarch iso from"
}

variable "pm_node" {
  type = string
  description = "Node onto which to deploy the VM"
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
variable "disk_size" {
  type        = number
  description = "Amount of disk memory allocated to the VM"
}
variable "ip_address" {
  type        = string
  description = "IP address of the VM"
}

variable "networks" {
  type = list(object({
      id      = number
      macaddr = string
      tag     = optional(number, 0)
  }))
}

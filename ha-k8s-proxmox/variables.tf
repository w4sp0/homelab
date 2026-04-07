variable "talos_control_configuration" {
  type = list(object({
    pm_mode = string
    vmid = number
    vm_name = string
    cpu_cores = number
    memory = number
    disk_size = string
    networks = list(object({
      id      = number
      macaddr = string
      tag     = number
    }))
  }))
}

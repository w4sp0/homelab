output "containers" {
  description = "Map of all created containers with their vmid, hostname and IP."

  value = {
    for name, mod in module.containers : name => {
      vmid       = mod.vmid
      hostname   = mod.hostname
      ip_address = mod.ip_address
      ssh        = mod.ssh_command
    }
  }
}

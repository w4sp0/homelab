talos_iso_file = "local:iso/metal-amd64.iso"

talos_control_configuration = [
  {
    pm_node = "pve0-nic0"
    vmid = 1110
    vm_name = "talos-control-1"
    cpu_cores = 2
    memory = 4096
    disk_size = "20G"
    networks = [
      { id = 0, macaddr = "BC:24:13:5F:39:D1" }
    ]
  },
  {
    pm_node = "pve2"
    vmid = 2110
    vm_name = "talos-control-2"
    cpu_cores = 2
    memory = 4096
    disk_size = "20G"
    networks = [
      { id = 0, macaddr = "BC:24:13:5F:39:D2" }
    ]
  },
  {
    pm_node = "pve3"
    vmid = 3110
    vm_name = "talos-control-3"
    cpu_cores = 2
    memory = 4096
    disk_size = "20G"
    networks = [
      { id = 0, macaddr = "BC:24:13:5F:39:D3" }
    ]
  },
]

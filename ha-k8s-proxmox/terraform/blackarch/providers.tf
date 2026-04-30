terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.104.0"
    }
  }
}


provider "proxmox" {
  endpoint  = "https://100.111.118.45:8006"
  api_token = var.pm_api_token
  insecure  = true

  ssh {
    agent    = true
    username = "root"
  }
}

terraform {
  required_providers {
    proxmox = {
      source = "Telemate/proxmox"
      version = ""
    }
  }
}

provider "proxmox" {
  pm_api_url = var.pm_api_url
  pm_user = var.pm_username
  pm_api_token_id = var.pm_api_token_id
  pm_api_token_secret = var.pm_api_token_secret
}

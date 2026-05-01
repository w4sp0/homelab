resource "proxmox_virtual_environment_container" "gitea_container" {
  description = "Managed by Terraform"

  node_name = "first-node"
  vm_id     = 100

  # newer linux distributions require unprivileged user namespaces
  unprivileged = true
  features {
    nesting = true
  }

  initialization {
    hostname = "gitea"

    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }

    user_account {
      keys = [
        trimspace(tls_private_key.gitea_container_key.public_key_openssh)
      ]
      password = random_password.gitea_container_password.result
    }
  }

  network_interface {
    name = "vmbr0"
    mac_address = 
  }

  disk {
    datastore_id = "local-lvm"
    size         = 4
  }

  operating_system {
    template_file_id = proxmox_virtual_environment_download_file.gitea_2504_lxc_img.id
    # Or you can use a volume ID, as obtained from a "pvesm list <storage>"
    # template_file_id = "local:vztmpl/jammy-server-cloudimg-amd64.tar.gz"
    type             = "gitea"
  }

  mount_point {
    # bind mount, *requires* root@pam authentication
    volume = "/mnt/bindmounts/shared"
    path   = "/mnt/shared"
  }

  mount_point {
    # volume mount, a new volume will be created by PVE
    volume = "local-lvm"
    size   = "10G"
    path   = "/mnt/volume"
  }

  mount_point {
    # volume mount, an existing volume will be mounted
    volume = "local-lvm:subvol-108-disk-101"
    size   = "10G"
    path   = "/mnt/data"
  }

  # To reference a mount point volume from another resource, use path_in_datastore:
  # mount_point {
  #   volume = other_container.mount_point[0].path_in_datastore
  #   size   = "10G"
  #   path   = "/mnt/shared"
  # }

  startup {
    order      = "3"
    up_delay   = "60"
    down_delay = "60"
  }
}

resource "proxmox_virtual_environment_download_file" "gitea_2504_lxc_img" {
  content_type = "vztmpl"
  datastore_id = "local"
  node_name    = "first-node"
  url          = "https://mirrors.servercentral.com/gitea-cloud-images/releases/25.04/release/gitea-25.04-server-cloudimg-amd64-root.tar.xz"
}

resource "random_password" "gitea_container_password" {
  length           = 16
  override_special = "_%@"
  special          = true
}

resource "tls_private_key" "gitea_container_key" {
  algorithm = "ED25519"
}

output "gitea_container_password" {
  value     = random_password.gitea_container_password.result
  sensitive = true
}

output "gitea_container_private_key" {
  value     = tls_private_key.gitea_container_key.private_key_pem
  sensitive = true
}

output "gitea_container_public_key" {
  value = tls_private_key.gitea_container_key.public_key_openssh
}

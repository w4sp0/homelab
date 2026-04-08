# Installation

Homelab installation instructions.

## Table of Contents

*   [Prerequisites](#prerequisites)
*   [Local tools](#local-tools)
*   [Proxmox setup](#proxmox-setup)
*   [Kubernetes cluster](#kubernetes-cluster)
*   [Qubes OS](#qubes-os)
*   [NixOS](#nixos)
*   [macOS](#macos)

## Prerequisites

*   3 Proxmox VE nodes with shared network (`10.0.0.0/24`)
*   Tailscale account with at least one Proxmox host on the tailnet
*   Talos Linux ISO uploaded to each Proxmox node
*   Git

## Local tools

This project uses [mise](https://mise.jdx.dev) to manage tool versions.

```sh
# Install mise (if not already installed)
curl https://mise.run | sh

# Install all project tools
cd ha-k8s-proxmox
mise install
```

This installs:

*   `opentofu` -- Infrastructure provisioning
*   `ansible` -- Configuration orchestration
*   `talosctl` -- Talos Linux management
*   `kubectl` -- Kubernetes CLI (install separately or add to mise.toml)

## Proxmox setup

### API token

Create an API token on one of the Proxmox nodes for OpenTofu:

1.  Navigate to Datacenter > Permissions > API Tokens.
2.  Create a token for `root@pam` (or a dedicated user).
3.  Record the token ID and secret.

### Tailscale subnet routing

To access the VM network (`10.0.0.0/24`) from your workstation:

1.  Install Tailscale on at least one Proxmox host.
2.  Advertise the subnet route:
    ```sh
    tailscale set --advertise-routes=10.0.0.0/24
    ```
3.  Approve the route in the Tailscale admin console.
4.  Enable IP forwarding on the Proxmox host:
    ```sh
    echo 1 > /proc/sys/net/ipv4/ip_forward
    ```
5.  Enable "Use Tailscale subnets" on your client.

### Talos ISO

Download the Talos Linux ISO and upload it to each Proxmox node:

```sh
# Download from https://www.talos.dev/latest/introduction/getting-started/
# Upload to Proxmox storage as local:iso/metal-amd64.iso
```

## Kubernetes cluster

See [ha-k8s-proxmox/README.md](../ha-k8s-proxmox/README.md) for detailed
instructions.

Quick start:

```sh
# 1. Configure credentials
cd ha-k8s-proxmox/terraform
cp secrets.auto.tfvars.example secrets.auto.tfvars
# Edit secrets.auto.tfvars with your Proxmox API credentials

# 2. Provision VMs
tofu init
tofu apply -var-file=values.tfvars

# 3. Configure and bootstrap cluster
cd ../ansible
ansible-playbook install.yaml

# 4. Get kubeconfig
talosctl --talosconfig ../rendered/talosconfig kubeconfig
kubectl get nodes
```

## Qubes OS

TODO: Document SaltStack formula installation.

## NixOS

TODO: Document flake-based NixOS configuration.

## macOS

TODO: Document nix-darwin setup.

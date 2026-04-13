# Homelab bootstrap strategy.

## Table of Contents

*   [Description](#description)
*   [Foundation](#foundation)
*   [Compute](#compute)
*   [Workstations](#workstations)

## Description

With multiple platforms and tools, bootstrapping a new environment requires
a specific order. This document describes the recommended sequence.

The order matters: later stages depend on infrastructure provisioned in
earlier stages. Within each stage, items can generally be set up in parallel.

## Foundation

Set up the physical and network infrastructure first. Everything else depends
on this layer.

1.  **Proxmox VE cluster**
    *   Install Proxmox on all physical nodes.
    *   Configure networking (bridges, VLANs if applicable).
    *   Ensure all nodes share the `10.0.0.0/24` network.

2.  **Tailscale overlay**
    *   Install Tailscale on each Proxmox host.
    *   Advertise subnet routes for VM networks.
    *   Approve routes in the admin console.
    *   Verify connectivity from your workstation.

3.  **Proxmox API access**
    *   Create API tokens for OpenTofu.
    *   Upload Talos ISO to each node's local storage.

## Compute

With the foundation in place, provision VMs and clusters.

1.  **Kubernetes cluster** ([ha-k8s-proxmox](../ha-k8s-proxmox/README.md))
    *   Provision VMs with OpenTofu.
    *   Configure and bootstrap with Ansible.
    *   Verify cluster health and VIP.

2.  **Additional VMs** (planned)
    *   DNS servers
    *   Media servers
    *   Other services

## Workstations

Workstation configuration is independent of the infrastructure above and can
be done in parallel.

1.  **macOS** (planned: [darwin](../darwin/README.md))
    *   Install Nix package manager.
    *   Apply nix-darwin configuration.

2.  **NixOS** ([nixos-config](../nixos-config/README.md))
    *   Boot from NixOS installer.
    *   Apply flake configuration.

3.  **Qubes OS** ([qubes-config](../qubes-config/README.md))
    *   Install Qubes OS.
    *   Apply SaltStack formulas.

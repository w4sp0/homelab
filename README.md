# homelab

Infrastructure as Code for a multi-platform homelab environment.

## Warning

**Warning**: Not ready for production, development only. Breaking changes can
and will be introduced. Configuration values are specific to this environment and must be adapted for other deployments.

## Table of Contents

*   [Description](#description)
*   [Architecture](#architecture)
*   [Installation](#installation)
*   [Usage](#usage)
*   [Contribute](#contribute)
*   [Project Structure](#project-structure)

## Description

This project manages the complete infrastructure of a personal homelab
spanning multiple platforms and operating systems. Each platform uses its
native or best-suited configuration management tooling:

*   **Proxmox VE**: OpenTofu for VM lifecycle, Ansible for orchestration
*   **Qubes OS**: SaltStack formulas
*   **NixOS**: Nix flakes
*   **macOS**: nix-darwin

The goal is reproducible, declarative infrastructure where every machine and
service can be rebuilt from this repository.

## Architecture

### Platforms

| Platform   | Tooling              | Purpose                              |
|------------|----------------------|--------------------------------------|
| Proxmox VE | OpenTofu, Ansible   | Hypervisor, VM provisioning          |
| Talos Linux| talosctl, Ansible    | Immutable Kubernetes nodes           |
| Qubes OS   | SaltStack            | Security-focused workstation         |
| NixOS      | Nix flakes           | Declarative Linux machines           |
| macOS      | nix-darwin           | Development workstation              |

### Network

| Subnet         | Purpose                     | Access                |
|----------------|-----------------------------|-----------------------|
| 10.0.0.0/24    | Proxmox VMs / Kubernetes    | Tailscale subnet route|

### Kubernetes Cluster

| Component       | Details                                |
|-----------------|----------------------------------------|
| Hypervisor      | Proxmox VE (3 nodes: pve0, pve2, pve3)|
| OS              | Talos Linux v1.12.6                    |
| Kubernetes      | v1.35.2                                |
| CNI             | Flannel                                |
| API Endpoint    | https://10.0.0.199:6443 (VIP)          |
| Control Planes  | 3 (static IPs: 142, 143, 144)         |
| Workers         | 6 (DHCP: 147-152)                     |

## Installation

See [docs/INSTALL.md](docs/INSTALL.md).

## Usage

After installation, refer to each subproject's README for platform-specific
usage instructions. For a guided setup of a new environment, see
[docs/BOOTSTRAP.md](docs/BOOTSTRAP.md).

## Contribute

See [docs/DESIGN.md](docs/DESIGN.md) for naming conventions, project
structure requirements, and other policies.

## Project Structure

```
homelab/
|-- docs/
|   |-- BOOTSTRAP.md              # New environment setup guide
|   |-- DESIGN.md                 # Conventions, policies, decisions
|   |-- INSTALL.md                # Prerequisites and installation
|   |-- TROUBLESHOOT.md           # Troubleshooting guide
|-- ha-k8s-proxmox/               # Talos Kubernetes on Proxmox
|   |-- ansible/                  # Cluster orchestration
|   |-- talos/                    # Machine config patches
|   |-- terraform/                # VM provisioning (OpenTofu)
|-- qubes-config/                 # Qubes OS SaltStack formulas (submodule)
|-- nixos-config/                 # NixOS flake configurations (submodule)
|-- darwin/                       # macOS nix-darwin configs (planned)
```

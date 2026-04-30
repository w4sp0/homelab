# Design

Homelab design document.

## Table of Contents

*   [Goal](#goal)
*   [Documentation](#documentation)
*   [Format](#format)
    *   [Readme](#readme)
    *   [File naming](#file-naming)
*   [Conventions](#conventions)
    *   [Platform tooling](#platform-tooling)
    *   [Resource naming](#resource-naming)
    *   [Network allocation](#network-allocation)
    *   [Secrets management](#secrets-management)
*   [Subproject structure](#subproject-structure)
*   [Upgrade procedures](#upgrade-procedures)

## Goal

Provide a reproducible, declarative homelab where every machine and service
can be rebuilt from a single repository. Each platform uses its native or
best-suited configuration management tool. Configuration should be minimal
and modular: only include what is strictly necessary for functionality.

No extraneous features should be included by default. Extra functionality
that increases attack surface or complexity can be provided via optional
modules that the user enables explicitly.

The project should remain maintainable by a single person. If the number of
managed services grows too large to keep track of, consolidate or remove
before adding more.

## Documentation

Markdown must follow
[Google's Markdown style guide](https://google.github.io/styleguide/docguide/style.html).

Documentation must not duplicate itself, but reference one another.
Reproducing instructions that can be found in upstream documentation is
discouraged unless the benefits of having a single source outweigh the
maintenance cost of keeping it current.

## Format

### Readme

Every subproject must have a README.md with at least the following sections:

*   Table of Contents
*   Description
*   Prerequisites
*   Installation
*   Usage

### File naming

1.  File names must use `-` as separator, not `_` (unless required by the
    language or tool, such as Python modules or Terraform variables).
2.  Configuration files should be named descriptively by function, not by
    sequence number.

## Conventions

### Platform tooling

Each platform has a designated configuration management tool. Do not mix
tooling across platforms unless there is a clear justification.

| Platform   | Tool           | Language/Format        |
|------------|----------------|------------------------|
| Proxmox VE | OpenTofu       | HCL                    |
| Talos Linux| talosctl       | YAML                   |
| Orchestration | Ansible     | YAML                   |

### Resource naming

Consistent naming across platforms makes resources identifiable at a glance.

#### Proxmox VMs

*   **Control plane**: `talos-control-N` (e.g., `talos-control-1`)
*   **Worker**: `talos-worker-N` (e.g., `talos-worker-1`)
*   **General VM**: `purpose-N` (e.g., `dns-1`, `media-1`)

#### VMID allocation

VMIDs follow a 3-digit convention:

|   Range   |   Platform    |
|-----------|---------------|
|   1xx     |   infra       |
|   2xx     |   kubernetes  |
|   3xx     |   security    |
|   4xx     |   lab         |
|   9xx     |   ephemeral   |

The second digit is a platform-defined subrole (e.g., kubernetes uses `0`
for control plane, `1` for worker). The third digit is the instance index
within that subrole.

Examples:

*   `200` = kubernetes, control plane, instance 0.
*   `213` = kubernetes, worker, instance 3.
*   `300` = security, pentest, instance 0.

#### MAC address allocation

MAC address allocation follows the standard Proxmox conventions, where the last
two octets are the `VMID` as big-endian hex.

Format: `BC:24:13:<platform>:<vmid_hi>:<vmid_lo>`

Examples:

*   VMID `213` -> `BC:24:13:02:00:D5`
*   VMID `300` -> `BC:24:13:03:01:2C`

NOTE: existing Talos VM MACs are grandfathered until natural rebuild.

#### Hostnames

*   Servers and infrastructure: `role-N` (e.g., `pve0`, `dns-1`)

#### VM tags

Every managed VM carries three required tag axes, in the following order:
`platform:` / `role:` / `stage:`.

|   Axis      |   Allowed values                                             |
|-------------|--------------------------------------------------------------|
| `platform:` | `kubernetes`, `security`, `infra`, `lab`                     |
| `role:`     | function (e.g. `control`, `worker`, `pentest`, `monitoring`) |
| `stage:`    | `dev`, `prod`                                                |

### Network allocation

| Subnet         | Purpose                              |
|----------------|--------------------------------------|
| 10.0.0.0/24    | Proxmox VM network                   |
| 10.0.0.1       | Gateway                              |
| 10.0.0.142-144 | Kubernetes control planes (static)   |
| 10.0.0.147-152 | Kubernetes workers (DHCP)            |
| 10.0.0.199     | Kubernetes API VIP                   |
| 100.x.x.x/10   | Tailscale overlay                    |

When adding new subnets or static IPs, update this table and the
corresponding subproject documentation.

### Secrets management

*   Secrets must never be committed to the repository.
*   Use `.gitignore` to exclude files containing secrets (e.g.,
    `secrets.auto.tfvars`, `rendered/`).
*   Terraform/OpenTofu secrets go in `secrets.auto.tfvars` (gitignored).
*   Talos machine configs and PKI are generated into `rendered/` (gitignored).
*   For future use, consider an external secrets manager (e.g., SOPS,
    age, or Vault).

## Subproject structure

Each subproject lives in its own top-level directory and must be
self-contained: it should be possible to understand and operate a subproject
by reading only its README and the top-level docs.

```bash
.
|-- docs
|   `-- adr
`-- ha-k8s-proxmox
    `-- terraform
        |-- blackarch
        `-- kubernetes
            `-- talos
                `-- patches
```

### Adding a new subproject

1.  Create a top-level directory with a descriptive name.
2.  Add a README.md following the format described above.
3.  Add a reference to the subproject in the root README.md.
4.  If the subproject introduces new network ranges, update the network
    allocation table in this document.

## Upgrade procedures

### Talos Linux upgrade

1.  Check the [Talos release notes](https://www.talos.dev/latest/introduction/releases/)
    for breaking changes.
2.  Update the ISO on all Proxmox hosts.
3.  Update `talosctl` locally (`mise install`).
4.  Perform a rolling upgrade using `talosctl upgrade`.

### Kubernetes upgrade

1.  Review the [Kubernetes changelog](https://kubernetes.io/releases/) for
    deprecations and breaking changes.
2.  Upgrade Talos first (Kubernetes version is tied to the Talos release).
3.  Verify all workloads after upgrade.

### Proxmox upgrade

1.  Follow the [Proxmox upgrade guide](https://pve.proxmox.com/wiki/Upgrade).
2.  Upgrade one node at a time to maintain cluster availability.
3.  Verify VM connectivity after each node upgrade.

### NixOS / nix-darwin upgrade

1.  Update flake inputs (`nix flake update`).
2.  Build and test locally before applying (`nixos-rebuild build`).
3.  Apply to the target machine.

### Qubes OS upgrade

1.  Subscribe to
    [qubes-announce](https://www.qubes-os.org/support/#qubes-announce) for
    release notifications.
2.  Follow the official upgrade procedure.
3.  Re-apply SaltStack formulas and verify qube functionality.

# Install

Homelab install and update guide.

## Table of Contents

*   [Installation](#installation)
    *   [Prerequisites](#prerequisites)
*   [Local tools](#local-tools)
*   [Proxmox setup](#proxmox-setup)
*   [Kubernetes cluster](#kubernetes-cluster)
*   [Qubes OS](#qubes-os)
*   [NixOS](#nixos)
*   [macOS](#macos)

## Installation

### Prerequisites

Your current setup needs to fulfill the following requisites:

*   Internet connection
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
*   `kubectl` -- Kubernetes CLI


### Repostiory

1. Clone the repository (if you made a fork, for the submodule(s) before clone and use your remote repository instead, the submodules will also be from your fork).

```sh
git clone --recurse-submodules https://github.com/w4sp0/homelab.git ~/homelab
```

2. Copy the [maintainer's signing key](https://github.com/w4sp0/w4sp0/raw/main/<KEY>.asc) to your text editor and save to the file `/home/<user>/w4s0-code.asc`.

3. Verify that the key fingerprint matches `<FINGERPRINT>`. You can use Sequoia-PGP or GnuPG for the fingerprint verification.

```sh
gpg --show-keys /tmp/w4sp-code.asc
# or
sq inspect w4sp0-code.asc
```

4. Import the verified key to your keyring:

```sh
gpg --import /tmp/w4sp0-code.asc
```

5. Enter the repository

```sh
cd ~/homelab
```

6. Verify the [commit or tag signature](https://www.qubes-os.org/security/verifying-signatures/#how-to-verify-signatures-on-git-repository-tags-and-commits) and expect a good signature, be surprised otherwise:

```sh
git verify-commit HEAD
```

In case the commit verification failed, you can try to verify if any tag pointing at that commit succeeds:

```sh
tag_list="$(git tag --points-at=HEAD)"
verified=0
for tag in ${tag_list}; do
  if git verify-tag "${tag}"
    verified=1
    break
  fi
done
if test "${verified}" = "0"; then
  printf '%s\n' "Failed to verify" >$2
  false
fi
```


## Proxmox setup

### API token

Create an API token on one of the Proxmox nodes for OpenTofu:

Reference: https://registry.terraform.io/providers/Telmate/proxmox/latest/docs#modifying-privileges

```sh
pveum role add <TerraformProv> -privs "Datastore.AllocateSpace Datastore.AllocateTemplate Datastore.Audit Pool.Allocate Pool.Audit Sys.Audit Sys.Console Sys.Modify VM.Allocate VM.Audit VM.Clone VM.Config.CDROM VM.Config.Cloudinit VM.Config.CPU VM.Config.Disk VM.Config.HWType VM.Config.Memory VM.Config.Network VM.Config.Options VM.Migrate VM.PowerMgmt SDN.Use"

pveum user add <terraform-prov>@pve --password <password>

pveum aclmod / -user <terraform-prov>@pve -role <TerraformProv>
```

From the GUI:

1.  Navigate to Datacenter > Permissions > API Tokens.
2.  Create a token for a dedicated user.
3.  Set the relevant permissions
3.  Record the token ID and secret.

### Tailscale subnet routing

To access the VM network (`10.0.0.0/24`) from your workstation on a different network:

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

# 3. Configure and bootstrap kubernetes cluster
cd ../ansible
ansible-playbook install.yaml

# 4. Get kubeconfig

talosctl --talosconfig ../rendered/talosconfig kubeconfig
kubectl get nodes
```

## NixOS

TODO: Document flake-based NixOS configuration.

## macOS

TODO: Document nix-darwin setup.

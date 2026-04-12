# ha-k8s-proxmox

Infrastructure-as-code for a homelab Proxmox cluster running a Talos
Kubernetes cluster, plus management services (Homepage dashboard).

Everything here is provisioned with Terraform and configured with Ansible.
No manual VM/LXC creation, no manual package installation — the repo is the
source of truth.

## Repo layout

```
.
├── terraform/              Proxmox VM + LXC provisioning
│   ├── main.tf             Talos VMs + service LXCs
│   ├── variables.tf
│   └── values.tfvars       Per-node sizing, MAC addresses, VMIDs
├── talos/
│   └── patches/            Per-node Talos machine config patches
├── rendered/               Generated Talos configs (gitignored)
├── ansible/
│   ├── ansible.cfg
│   ├── inventory.yaml      SSH inventory for service LXCs
│   ├── install.yaml        Talos cluster bring-up (runs on localhost)
│   ├── deploy-homepage.yaml  Homepage LXC configuration (SSH)
│   └── tasks/              Task files included by the playbooks above
└── homepage/               Homepage dashboard config (versioned)
    ├── docker-compose.yaml
    └── config/             settings, services, widgets, bookmarks
```

## Cluster overview

- **Proxmox nodes:** `pve0-nic0`, `pve2`, `pve3`
- **Talos k8s:** 3 control plane VMs + 6 worker VMs
- **Management services:** Homepage dashboard in an unprivileged LXC on `pve0-nic0`
- **Remote access:** Tailscale runs on the Proxmox hosts and port-forwards
  into LAN IPs. Services don't run tailscaled themselves.

## Prerequisites

On your workstation:
- `terraform` (or `opentofu`)
- `ansible` with `ansible.posix` collection (`ansible-galaxy collection install ansible.posix`)
- `talosctl`
- SSH key that matches `lxc_ssh_public_keys` in `terraform/values.tfvars`

On Proxmox:
- API token configured; credentials in `terraform/secrets.auto.tfvars`
- Talos ISO uploaded to `local:iso/metal-amd64.iso`
- Debian 13 LXC template downloaded: `pveam download local debian-13-standard_13.1-2_amd64.tar.zst` (or whatever the current version is — check `pveam available --section system | grep debian-13` and update `lxc_template` in `terraform/values.tfvars` accordingly)

On your network:
- DHCP reservations matching the MAC addresses in `terraform/values.tfvars`
  (Talos nodes → `10.0.0.142`–`10.0.0.152`, homepage LXC → `10.0.0.158`)

## Talos cluster bring-up

```sh
# 1. Create the Proxmox VMs
cd terraform
terraform apply -var-file=values.tfvars

# 2. Generate configs, apply them, bootstrap the cluster
cd ../ansible
ansible-playbook install.yaml
```

Rendered Talos configs land in `rendered/`. Use `rendered/talosconfig` with
`talosctl` to manage the cluster.

## Homepage deployment

Homepage runs in an unprivileged Debian 13 LXC (`VMID 1130`) on `pve0-nic0`,
with Docker inside, reachable over Tailscale via a host-level port-forward.

### First-time setup

1. **Download the Debian 13 template on `pve0-nic0`** (see prerequisites).
2. **Reserve a DHCP lease** on your network: MAC `BC:24:13:5F:39:F1` → `10.0.0.158`.
3. **Set your SSH public key** in `terraform/values.tfvars` (`lxc_ssh_public_keys`).
4. **Configure a Tailscale port-forward** on `pve0-nic0`: host `:8080` → `10.0.0.158:3000`.

### Deploy

```sh
# Create the LXC
cd terraform
terraform apply -var-file=values.tfvars

# Sanity-check SSH
ssh root@10.0.0.158 'hostname'

# Install Docker + deploy homepage
cd ../ansible
ansible-playbook deploy-homepage.yaml
```

Open `http://pve0-nic0:8080` over Tailscale.

### Iterating on the dashboard

Edit YAML under `homepage/config/`, then re-run:

```sh
cd ansible
ansible-playbook deploy-homepage.yaml
```

The playbook rsyncs changes and restarts the container only when config
actually changed. Safe to re-run any time.

### Tear down

```sh
cd terraform
terraform destroy -var-file=values.tfvars -target=proxmox_lxc.homepage
```

## Conventions

**VMID scheme:** `{node}{category}{index}` where the first digit encodes
the node (`1`=pve0, `2`=pve2, `3`=pve3), the middle two encode the
category (`11`=control plane, `12`=worker, `13`=service), and the last
is the index.

| Role           | Node     | VMID |
| -------------- | -------- | ---- |
| Control plane  | pve0     | 1110 |
| Control plane  | pve2     | 2110 |
| Control plane  | pve3     | 3110 |
| Worker         | pve0     | 1120, 1121 |
| Worker         | pve2     | 2120, 2121 |
| Worker         | pve3     | 3120, 3121 |
| Homepage (LXC) | pve0     | 1130 |

**MAC scheme:** `BC:24:13:5F:39:{category}{index}` — `D?` for control
plane, `E?` for workers, `F?` for services. MACs are pinned in Terraform
so DHCP reservations stay stable across rebuilds.

**Host port-forwards on `pve0-nic0`** (keep this table in sync when
adding services):

| Host port | Target              | Service  |
| --------- | ------------------- | -------- |
| `8080`    | `10.0.0.158:3000`   | Homepage |

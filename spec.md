# Homelab Infrastructure Specification

Target-state specification for the homelab infrastructure. This document
describes the desired end state — not the implementation order.

## Table of Contents

*   [Hardware inventory](#hardware-inventory)
*   [Machine roles](#machine-roles)
*   [Networking](#networking)
*   [DNS](#dns)
*   [Certificates](#certificates)
*   [Authentication](#authentication)
*   [Monitoring and alerting](#monitoring-and-alerting)
*   [Kubernetes cluster](#kubernetes-cluster)
*   [AI and ML infrastructure](#ai-and-ml-infrastructure)
*   [Security lab](#security-lab)
*   [Git workflow](#git-workflow)
*   [Qubes OS integration](#qubes-os-integration)
*   [Access control](#access-control)
*   [Proxmox node workload placement](#proxmox-node-workload-placement)
*   [VMID scheme](#vmid-scheme)
*   [MAC address scheme](#mac-address-scheme)
*   [Open items](#open-items)

## Hardware inventory

### Proxmox cluster

| Node | CPU | RAM | Storage | GPU | Role |
|------|-----|-----|---------|-----|------|
| pve1 (PowerEdge R730xd) | Xeon E5-2667 v3 | 128 GB | 4 TB SSD, 42 TB HDD (HW RAID) | None | Infrastructure anchor + security lab |
| pve2 | AMD Ryzen 7 | 82 GB | 1 TB SSD, 4 TB ZFS | RTX 2080 Ti (11 GB VRAM) | Primary AI/GPU compute |
| pve3 | Intel i5 | 64 GB | 256 GB SSD | RTX 2060 (6 GB VRAM) | Secondary AI/GPU compute |

### Workstations and auxiliary machines

| Machine | Specs | OS | Role |
|---------|-------|----|------|
| ThinkPad | Powerful Intel, 32 GB RAM | Qubes OS | Primary technical workstation (DevOps, AI, development) |
| MacBook Air M2 | Apple M2, 24 GB RAM | macOS | Work (non-technical tasks) |
| Mac Mini M1 | Apple M1, 16 GB RAM | macOS | Personal use |
| Lenovo laptop | Weak CPU, 8 GB RAM | NixOS | PAW (Privileged Access Workstation) |
| Dell Inspiron | Intel i5, 32 GB RAM, 512 GB SSD + 2 TB HDD + 12 TB USB | NixOS | Backup / DR node |

### Network equipment

| Device | Role |
|--------|------|
| pfSense router | Gateway, firewall, DNS resolver |
| Unmanaged switch | L2 connectivity (no VLAN support) |

## Machine roles

### Proxmox cluster (3 nodes)

All virtualized workloads run here. Each node runs a Kubernetes control
plane and workers, plus role-specific VMs.

### ThinkPad (Qubes OS) — technical workstation

Development, DevOps, and operational use. Connects to infrastructure via
Tailscale. Privileged admin operations go through the PAW, not this
machine.

### Lenovo (NixOS) — Privileged Access Workstation (PAW)

Follows the ANSSI PAW framework. Hardened NixOS configuration with only
administrative tools installed: `talosctl`, `kubectl`, `tofu`, `ansible`,
`ssh`. No browser, no email, no general-purpose software. Kanidm
MFA-enforced admin account. Full infrastructure access via Tailscale.

### Dell Inspiron (NixOS) — backup / DR node

Off-cluster backup target. Storage: 512 GB SSD (OS + cache), 2 TB HDD
(primary backup repository), 12 TB USB (secondary copy). Holds replicas
of critical data. Backup strategy to be designed separately.

### MacBook Air — work

Service-level access only: Homepage, Grafana, Gitea, Open WebUI.

### Mac Mini — personal

Minimal access: Homepage, Open WebUI.

## Networking

### Topology

Single flat subnet (`10.0.0.0/24`) with all Proxmox nodes and VMs on
`vmbr0`. pfSense is the gateway at `.1`. Physical connectivity via an
unmanaged switch (no VLAN support).

Segmentation is achieved through:

*   **pfSense firewall aliases** — group IPs by function (infrastructure,
    K8s, AI, security lab) and apply inter-group rules.
*   **Proxmox host firewall** — per-VM firewall rules on each Proxmox
    node.
*   **Kubernetes network policies** — Cilium-enforced pod-to-pod
    isolation within the cluster.
*   **Tailscale ACLs** — device-level access control for remote access.

### IP allocation

```
10.0.0.1          pfSense gateway
10.0.0.2          pve0-nic0 (management) [TODO: currently .10]
10.0.0.3          pve2 (management) [current]
10.0.0.4          pve3 (management) [current: .3]
10.0.0.5-9        Reserved (future Proxmox nodes)

10.0.0.10         step-ca (internal CA)
10.0.0.11         kanidm (SSO / IdP)
10.0.0.12         victoria-metrics
10.0.0.13         grafana
10.0.0.14         gitea
10.0.0.15         homepage
10.0.0.16         victoria-logs
10.0.0.17         ntfy (push notifications)
10.0.0.18-19      Reserved (future infrastructure services)

10.0.0.20         Kubernetes cluster 1 API VIP
10.0.0.21         K8s cluster 1 control plane 1 (pve0)
10.0.0.22         K8s cluster 1 control plane 2 (pve2)
10.0.0.23         K8s cluster 1 control plane 3 (pve3)
10.0.0.24-29      Reserved (future clusters VIP + control planes)

10.0.0.31         K8s cluster 1 worker 1 (pve0)
10.0.0.32         K8s cluster 1 worker 2 (pve0)
10.0.0.33         K8s cluster 1 worker 3 (pve2)
10.0.0.34         K8s cluster 1 worker 4 (pve2)
10.0.0.35         K8s cluster 1 worker 5 (pve3)
10.0.0.36         K8s cluster 1 worker 6 (pve3)
10.0.0.37-49      Reserved (future cluster workers)

10.0.0.51         ai-gpu-1 (pve2, RTX 2080 Ti)
10.0.0.52         ai-gpu-2 (pve3, RTX 2060)
10.0.0.53-59      Reserved (future AI/ML)

10.0.0.61         blackarch (pve0)
10.0.0.62         remnux (pve0)
10.0.0.63-79      Reserved (future security lab)

10.0.0.80-99      Reserved (future services)
10.0.0.100-199    DHCP pool (dynamic assignments)
10.0.0.200-254    Reserved
```

### pfSense firewall aliases

Group IPs into aliases for firewall rule authoring:

| Alias | Members | Purpose |
|-------|---------|---------|
| `PROXMOX_MGMT` | .2-.4 | Proxmox node management interfaces |
| `INFRA_SERVICES` | .10-.17 | Infrastructure LXCs (CA, IdP, monitoring, git) |
| `K8S_CONTROL` | .20-.23 | Kubernetes API VIP + control planes |
| `K8S_WORKERS` | .31-.36 | Kubernetes worker nodes |
| `AI_GPU` | .51-.52 | GPU compute VMs |
| `SECURITY_LAB` | .61-.62 | Pentesting and malware analysis VMs |

### Remote access

All remote access is via **Tailscale**. No services are exposed to the
public internet (the blog at `wassp.dev` runs on GitHub Pages, outside
this infrastructure).

*   Proxmox hosts advertise subnet route `10.0.0.0/24` via Tailscale.
*   Tailscale split DNS routes `homelab.internal` queries to pfSense.
*   Tailscale ACLs enforce per-device access (see
    [Access control](#access-control)).

## DNS

### Domains

| Domain | Scope | Managed by |
|--------|-------|------------|
| `wassp.dev` | Public (blog, future public services) | Cloudflare |
| `homelab.internal` | Private (all internal services) | pfSense DNS Resolver |

The `.internal` TLD is ICANN-reserved for private use. No split-horizon
DNS required — the two domains are entirely separate.

### Resolution

pfSense DNS Resolver (Unbound) handles the `homelab.internal` zone via
host overrides:

| Name | IP |
|------|----|
| `ca.homelab.internal` | 10.0.0.10 |
| `auth.homelab.internal` | 10.0.0.11 |
| `metrics.homelab.internal` | 10.0.0.12 |
| `grafana.homelab.internal` | 10.0.0.13 |
| `gitea.homelab.internal` | 10.0.0.14 |
| `home.homelab.internal` | 10.0.0.15 |
| `logs.homelab.internal` | 10.0.0.16 |
| `ntfy.homelab.internal` | 10.0.0.17 |
| `k8s.homelab.internal` | 10.0.0.20 |
| `ai.homelab.internal` | 10.0.0.51 |
| `ai2.homelab.internal` | 10.0.0.52 |

LAN clients use pfSense as their DNS server. Remote clients resolve
`homelab.internal` via Tailscale split DNS pointing to pfSense.

### Future: PiHole

PiHole is planned as a future addition for ad-blocking and DNS
filtering. When deployed, it will sit between clients and pfSense:
clients query PiHole, PiHole forwards to pfSense for
`homelab.internal`, and to upstream resolvers for everything else.

## Certificates

### Internal CA: step-ca (Smallstep)

An internal ACME-capable certificate authority runs in an LXC on pve0
at `ca.homelab.internal` (10.0.0.10).

**Responsibilities:**

*   Issue TLS certificates for all `*.homelab.internal` services.
*   Provide ACME endpoints for automated certificate renewal.
*   Issue client certificates if needed for mTLS.

**Root CA trust distribution:**

| Target | Method |
|--------|--------|
| Proxmox nodes | Ansible (install root cert to system trust store) |
| Talos K8s nodes | Talos machine config (`machine.files` or `machine.certSANs`) |
| Qubes OS (ThinkPad) | SaltStack formula (new: install root cert in relevant qubes) |
| NixOS machines (PAW, backup) | NixOS configuration (`security.pki.certificateFiles`) |
| macOS (MacBook Air, Mac Mini) | nix-darwin or manual trust via Keychain |

**Integration with Kubernetes:**

cert-manager runs in the cluster with a step-ca ACME ClusterIssuer.
Services in K8s request certificates via Certificate resources
or Gateway API TLS configuration.

## Authentication

### Identity provider: Kanidm

Kanidm runs in an LXC on pve0 at `auth.homelab.internal` (10.0.0.11).

**Capabilities:**

*   OIDC / OAuth2 provider
*   LDAP compatibility
*   WebAuthn / passkey support
*   Built-in MFA enforcement
*   RADIUS (if needed for network auth)

**Integration points:**

| Service | Protocol | Notes |
|---------|----------|-------|
| Proxmox VE | OIDC realm | SSO login to Proxmox web UI |
| Gitea | OAuth2 | SSO login |
| Grafana | OAuth2 (generic) | SSO login, role mapping |
| Kubernetes | OIDC | Talos API server `--oidc-*` flags; RBAC groups from Kanidm |
| PAW (NixOS) | PAM / LDAP | MFA-enforced admin login |

**User groups (for RBAC):**

| Group | Access level |
|-------|-------------|
| `infra-admin` | Full Proxmox + K8s cluster-admin. PAW only. |
| `developer` | K8s dev/staging namespaces, Gitea push, AI endpoints |
| `viewer` | Grafana read-only, Homepage, Open WebUI |

## Monitoring and alerting

### Metrics: VictoriaMetrics

Single-node VictoriaMetrics instance in an LXC on pve0 at
`metrics.homelab.internal` (10.0.0.12).

**Collection architecture:**

*   **vmagent** on each Proxmox host — scrapes local exporters, remote-
    writes to VictoriaMetrics.
*   **node-exporter** on each Proxmox host — hardware and OS metrics.
*   **pve-exporter** — Proxmox-specific metrics (VM status, storage,
    cluster health).
*   **kube-state-metrics** in K8s — Kubernetes object state.
*   **kubelet metrics** — container-level resource usage.

**Data retention:** Stored on pve0 HDD (42 TB available). Retention
period configured based on ingestion rate (start with 1 year).

### Logs: VictoriaLogs

VictoriaLogs instance in an LXC on pve0 at `logs.homelab.internal`
(10.0.0.16).

**Log sources:**

*   Proxmox host syslogs
*   Kubernetes pod logs (via log collection agent in the cluster)
*   LXC service logs (step-ca, kanidm, gitea, etc.)

### Dashboards: Grafana

Grafana in an LXC on pve0 at `grafana.homelab.internal` (10.0.0.13).

*   Datasources: VictoriaMetrics (Prometheus-compatible), VictoriaLogs.
*   Authentication: Kanidm OIDC.
*   Dashboards: Proxmox node health, K8s cluster overview, per-service
    dashboards, AI GPU utilization.

### Alerting: vmalert + Ntfy

*   **vmalert** evaluates alerting rules against VictoriaMetrics data.
*   Alerts route to **Alertmanager** which forwards to **Ntfy**.
*   **Ntfy** runs in an LXC on pve0 at `ntfy.homelab.internal`
    (10.0.0.17). Self-hosted push notification service with mobile and
    desktop apps.

**Alert categories:**

*   Node down (Proxmox host or K8s node unreachable)
*   Disk usage > threshold
*   K8s pod crash-looping or OOMKilled
*   Certificate expiry approaching
*   GPU temperature / utilization anomalies

## Kubernetes cluster

### Cluster identity

| Property | Value |
|----------|-------|
| Cluster name | `cluster-1` |
| OS | Talos Linux |
| CNI | Cilium (replaces Flannel) |
| Ingress | Cilium Gateway API |
| API endpoint | `https://10.0.0.20:6443` (VIP) |
| Control planes | 3 (one per Proxmox node, static IPs .21-.23) |
| Workers | 6 (two per Proxmox node, .31-.36) |

### CNI: Cilium

Cilium replaces Flannel as the CNI. Talos machine config must disable
the default Flannel CNI and configure Cilium. Cilium provides:

*   eBPF-based networking (higher performance than iptables)
*   Native Gateway API implementation (no separate ingress controller)
*   CiliumNetworkPolicy for fine-grained pod-to-pod isolation
*   Hubble for network observability

### Namespace structure

| Namespace | Purpose | Resource share |
|-----------|---------|----------------|
| `kube-system` | Talos/K8s system + Cilium | System |
| `cert-manager` | Automated TLS via step-ca ACME | Minimal |
| `monitoring` | In-cluster vmagent, kube-state-metrics, node-exporter DaemonSet | ~10% |
| `prod` | Production workloads | ~40% |
| `staging` | Staging/testing (mirrors prod config, smaller quotas) | ~25% |
| `dev` | Development (relaxed policies, lowest priority) | ~15% |
| `ai` | ML pipeline components (model registry, job scheduling) | ~10% |

### Isolation

*   **CiliumNetworkPolicy:** Deny cross-namespace traffic by default.
    Explicit allow rules for required flows (e.g., monitoring scraping
    all namespaces).
*   **ResourceQuotas:** Per-namespace CPU and memory limits.
*   **RBAC:** Tied to Kanidm OIDC groups. `infra-admin` gets
    cluster-admin. `developer` gets access to dev/staging namespaces.

### Worker sizing

| Node | Workers | RAM per worker | Cores per worker | Total |
|------|---------|---------------|-----------------|-------|
| pve0 | 2 | 20 GB | 6 | 40 GB |
| pve1 | 2 | 16 GB | 4 | 32 GB |
| pve2 | 2 | 12 GB | 4 | 24 GB |
| **Total** | **6** | | | **96 GB** |

### In-cluster services

*   **cert-manager** with step-ca ACME ClusterIssuer
*   **Cilium** with Gateway API CRDs
*   **vmagent** (DaemonSet) for metrics collection
*   **kube-state-metrics** for K8s object metrics
*   **Gitea Actions runners** (pods) for local CI/CD

## AI and ML infrastructure

### Primary GPU VM (pve1)

| Property | Value |
|----------|-------|
| VMID | 25001 |
| IP | 10.0.0.51 (`ai.homelab.internal`) |
| GPU | RTX 2080 Ti (11 GB VRAM, PCI passthrough) |
| RAM | 24 GB |
| Cores | 8 |
| Storage | Local SSD + NFS mount from pve2 ZFS (4 TB, models/datasets) |

**Software stack:**

*   NVIDIA drivers + CUDA toolkit
*   Ollama — LLM inference API (serves 7B-13B quantized models)
*   Open WebUI — browser-based chat interface
*   MLflow — experiment tracking
*   Python + PyTorch — training and fine-tuning

### Secondary GPU VM (pve2)

| Property | Value |
|----------|-------|
| VMID | 35001 |
| IP | 10.0.0.52 (`ai2.homelab.internal`) |
| GPU | RTX 2060 (6 GB VRAM, PCI passthrough) |
| RAM | 16 GB |
| Cores | 4 |
| Storage | Local SSD + NFS mount from pve2 ZFS |

**Software stack:**

*   NVIDIA drivers + CUDA toolkit
*   Ollama — smaller/specialized models (embeddings for RAG, Whisper
    speech-to-text, small coding models)
*   Batch fine-tuning workloads

### Architecture

The two GPU VMs are independent Ollama instances at different IPs.
Clients choose which endpoint to hit based on model requirements. There
is no automatic load balancing between them.

Models are stored on pve1's 4 TB ZFS pool and shared to pve3 via NFS.

The Kubernetes `ai` namespace runs orchestration components (model
registry, job scheduling) while actual GPU compute stays on the
dedicated VMs outside K8s.

### GPU passthrough

Both GPUs are already configured for VFIO passthrough on the Proxmox
hosts. See
[ha-k8s-proxmox/docs/proxmox-gpu-passthrough.md](ha-k8s-proxmox/docs/proxmox-gpu-passthrough.md)
for the host preparation runbook and recorded PCI IDs.

## Security lab

### Placement

All security lab VMs run on pve0-nic0 (128 GB RAM, 42 TB HDD) for
storage headroom.

### VMs

| VM | VMID | IP | RAM | Disk | Purpose |
|----|------|----|-----|------|---------|
| BlackArch | 16001 | 10.0.0.61 | 8 GB | 50 GB | Penetration testing toolkit |
| REMnux | 16002 | 10.0.0.62 | 8 GB | 100 GB | Malware analysis sandbox |

### Scope

BlackArch and REMnux cover current pentesting and malware analysis
needs. Additional VMs (OSINT, vulnerable targets, network analysis) can
be added later using the reserved range (.63-.79).

BlackArch includes Kubernetes security tools (trivy, kube-hunter,
kube-bench, kubeaudit) from the existing Packer build.

## Git workflow

### Three-tier architecture

```
dev-qube (Qubes) --> sys-git (Qubes) --> GitHub (source of truth)
                                             |
                                             v (auto-mirror)
                                         Gitea (local)
                                             |
                                             v
                                   Gitea Actions (K8s runners)
```

1.  **GitHub** — Source of truth. Authoritative remote for all repos.
    Public CI via GitHub Actions.
2.  **sys-git (Qubes OS)** — Inter-qube git transfer. Middleman between
    dev-qube and infra-admin qube. Extra backup.
3.  **Gitea** — Mirrors from GitHub (read-only). Runs local CI/CD via
    Gitea Actions with Kubernetes-based runners.

### Gitea

Runs in an LXC on pve0 at `gitea.homelab.internal` (10.0.0.14).

*   Mirrors all repos from GitHub automatically.
*   Gitea Actions provides local CI/CD with runners in the K8s cluster.
*   Local CI benefits: pipelines test against the real K8s cluster,
    run `tofu plan` against Proxmox, validate Ansible playbooks — things
    GitHub Actions cannot do without exposing the infrastructure.
*   Gitea Actions is ~85-90% compatible with GitHub Actions (same YAML
    syntax, most marketplace actions work).

### Authentication

Gitea authenticates via Kanidm OAuth2.

## Qubes OS integration

The ThinkPad runs Qubes OS and is the primary technical workstation.

### Qube-to-infrastructure mapping

| Qube | Type | Role |
|------|------|------|
| `sys-tailscale` | Service qube | Network access to 10.0.0.0/24 via Tailscale subnet routing |
| `infra-admin` | AppVM | Infrastructure management: talosctl, kubectl, tofu, ansible |
<!-- TODO: pushes to GitHub/Gitea are not possible through sys-git there needs to be another mechanism -->
| `dev` | AppVM | Development work, pushes to Gitea/GitHub via sys-git |
| `osint` | AppVM | OSINT tools, connects to OSINT VMs when added |
| `disp-pentest` | DispVM | Ephemeral pentesting sessions, connects to BlackArch/REMnux |

### Certificate trust

The step-ca root CA certificate must be installed in relevant qubes via
a SaltStack formula. At minimum: `infra-admin`, `dev`, and the template
VMs they inherit from.

### Git flow

`dev` qube pushes to `sys-git` (inter-qube). `sys-git` pushes to
GitHub. `infra-admin` pulls from `sys-git` for infrastructure changes.

## Access control

### Tailscale ACLs

| Device | Access |
|--------|--------|
| Lenovo PAW | Full: all IPs in 10.0.0.0/24 |
| ThinkPad (Qubes) | Services: Gitea, Grafana, Homepage, Open WebUI, AI endpoints, K8s API (dev/staging only) |
| MacBook Air | Limited: Homepage, Grafana, Gitea, Open WebUI |
| Mac Mini | Minimal: Homepage, Open WebUI |

The PAW is the only device with unrestricted infrastructure access.
Administrative operations (Proxmox management, K8s cluster-admin,
Ansible runs) must be performed from the PAW.

### Tailscale split DNS

All devices resolve `homelab.internal` via Tailscale split DNS,
which routes queries to pfSense's DNS Resolver.

### Kanidm RBAC

| Group | Proxmox | K8s | Gitea | Grafana |
|-------|---------|-----|-------|---------|
| `infra-admin` | Full access | cluster-admin | Admin | Admin |
| `developer` | No access | dev + staging namespaces | Push | Editor |
| `viewer` | No access | Read-only | Read | Viewer |

## Proxmox node workload placement

### pve0-nic0 (128 GB RAM, Xeon, 4 TB SSD, 42 TB HDD)

**Role:** Infrastructure anchor + security lab.

| Workload | Type | RAM | Disk | VMID |
|----------|------|-----|------|------|
| step-ca | LXC | 512 MB | 4 GB | 10101 |
| kanidm | LXC | 4 GB | 8 GB | 10102 |
| victoria-metrics | LXC | 4 GB | 100 GB (HDD) | 10103 |
| grafana | LXC | 1 GB | 4 GB | 10104 |
| gitea | LXC | 2 GB | 20 GB | 10105 |
| homepage | LXC | 512 MB | 4 GB | 10106 |
| victoria-logs | LXC | 4 GB | 200 GB (HDD) | 10107 |
| ntfy | LXC | 512 MB | 2 GB | 10108 |
| K8s control-1 | VM | 4 GB | 20 GB | 11001 |
| K8s worker-1 | VM | 20 GB | 40 GB | 11101 |
| K8s worker-2 | VM | 20 GB | 40 GB | 11102 |
| BlackArch | VM | 8 GB | 50 GB | 16001 |
| REMnux | VM | 8 GB | 100 GB | 16002 |

**Total RAM:** ~77 GB used, ~51 GB headroom.

**Storage:** SSD for VM/LXC OS disks. HDD for VictoriaMetrics data,
VictoriaLogs, Gitea repositories, and backups.

### pve1

**Role:** Primary AI/GPU compute.

| Workload | Type | RAM | Disk | VMID |
|----------|------|-----|------|------|
| K8s control-2 | VM | 4 GB | 20 GB | 21001 |
| K8s worker-3 | VM | 16 GB | 40 GB | 21101 |
| K8s worker-4 | VM | 16 GB | 40 GB | 21102 |
| ai-gpu-1 | VM | 24 GB | 100 GB | 25001 |

**Total RAM:** ~60 GB used, ~22 GB headroom.

ZFS ARC gets ~18 GB for read caching, critical for NFS-serving AI
models to pve3.

**Storage:** 1 TB SSD for VM disks. 4 TB ZFS pool for AI models,
datasets, and NFS exports.

### pve3 (64 GB RAM, Intel i5, 256 GB SSD, RTX 2060)

**Role:** Secondary AI/GPU compute.

| Workload | Type | RAM | Disk | VMID |
|----------|------|-----|------|------|
| K8s control-3 | VM | 4 GB | 20 GB | 31001 |
| K8s worker-5 | VM | 12 GB | 40 GB | 31101 |
| K8s worker-6 | VM | 12 GB | 40 GB | 31102 |
| ai-gpu-2 | VM | 16 GB | 50 GB | 35001 |

**Total RAM:** ~44 GB used, ~20 GB headroom.

**Storage:** ~150 GB used of 256 GB SSD. AI models served via NFS from
pve2 (not stored locally).

## VMID scheme

5-digit format: **NCCII**

| Field | Range | Meaning |
|-------|-------|---------|
| N | 1-9 | Proxmox node (1=pve0, 2=pve2, 3=pve3) |
| CC | 01-99 | Category (see below) |
| II | 01-99 | Instance within category |

### Category codes

| CC | Meaning |
|----|---------|
| 01-09 | Infrastructure services |
| 10 | Kubernetes cluster 1 — control planes |
| 11 | Kubernetes cluster 1 — workers |
| 20 | Kubernetes cluster 2 — control planes |
| 21 | Kubernetes cluster 2 — workers |
| 30/31 | Kubernetes cluster 3 (and so on) |
| 50 | AI / ML |
| 60 | Security lab |
| 90 | Templates (Packer-built) |

**Scales to:** 9 Proxmox nodes, 9+ Kubernetes clusters, 99 instances
per category per node.

## MAC address scheme

Format: `BC:24:13:5F:39:XY`

| X | Category |
|---|----------|
| A | Infrastructure services |
| D | Kubernetes control planes |
| E | Kubernetes workers |
| F | AI / ML |
| B | Security lab |

Y = instance index (hex, 0-F).

MACs are pinned in Terraform so DHCP reservations stay stable across
rebuilds.

## Open items

The following items are identified but deferred for separate design:

*   **TODO:** Migrate Proxmox management IPs to .2/.3/.4 scheme (requires
    physical access for corosync reconfiguration). Current: pve0=.10,
    pve2=.2, pve3=.3.
*   **TODO:** Design backup strategy for the Dell Inspiron DR node.
    Targets: Gitea, VictoriaMetrics/Logs, Talos etcd, Kanidm, step-ca
    PKI, Terraform state, Qubes OS backups. Tools and offsite strategy
    TBD.
*   **TODO:** PiHole deployment for DNS filtering (sits between clients
    and pfSense).
*   **TODO:** Managed switch upgrade for VLAN-based network segmentation
    (replaces current pfSense alias approach).

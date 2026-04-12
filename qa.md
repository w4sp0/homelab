# Q&A — Homelab Infrastructure Spec

This file records each question and answer verbatim as we develop the specification.

---

## Q1 — Network segmentation approach

**Question:** You have everything on a flat 10.0.0.0/24 today with an unmanaged switch. For network segmentation without VLANs, I see two realistic approaches: (A) use Proxmox SDN with VXLAN overlays to create isolated virtual networks across all three nodes — this gives you real L2 isolation for security-lab, AI, and infra traffic without touching the physical switch; or (B) stay on the single flat subnet, carve it into IP ranges by function, and rely on pfSense firewall aliases + Proxmox host firewall rules for access control between groups. Which approach do you want to start with?

**Answer:** Flat subnet + firewall rules. Keep everything on 10.0.0.0/24, use IP range groupings with pfSense aliases and Proxmox firewall. Simpler, less isolation.

---

## Q2 — IP allocation migration strategy

**Question:** The IP allocation I proposed has infrastructure services in .10-.19 and Kubernetes in .20-.49, which means migrating from the current IPs (.142-.152, .158, .199). This is a breaking change — you'd need to update DHCP reservations, Talos patches, Terraform configs, and the K8s VIP. Do you want to: (A) adopt the clean new scheme and accept the one-time migration, or (B) keep the current K8s IPs (.142-.152, .199) and only apply the new scheme to new services?

**Answer:** Clean migration. Adopt the new .10-.79 scheme fully. One-time reprovisioning of the cluster and services. Clean slate going forward.

---

## Q3 — DNS and certificate domains

**Question:** For the internal certificate authority, I'm recommending step-ca (Smallstep) in an LXC on pve0. It would issue certs for all internal services. What domain should be used for internal services, and should it be separate from the public wassp.dev?

**Answer:** Use `.internal` TLD for all private services, keep `wassp.dev` for public-facing resources only. Rationale: avoids split-horizon DNS issues, no external dependency for internal resolution, ICANN-reserved TLD with no collision risk.

**Follow-up — specific internal domain name:**

**Question:** What should the internal domain be? This will be used for all internal service names (e.g., grafana.\<domain\>, gitea.\<domain\>, authentik.\<domain\>). pfSense DNS Resolver would handle this zone.

**Answer:** `homelab.internal`. Services will be: grafana.homelab.internal, gitea.homelab.internal, etc.

---

## Q6 — Monitoring stack

**Question:** For monitoring with Victoria Metrics: the plan is a single-node VictoriaMetrics instance in an LXC on pve0 (it has the most RAM and storage for retention). Grafana in a separate LXC for dashboards, authenticated via Kanidm OIDC. For metrics collection, vmagent would scrape: node-exporter on Proxmox hosts, pve-exporter for Proxmox-specific metrics, and kube-state-metrics + kubelet in K8s. Two questions: (1) Do you want log aggregation too (e.g., VictoriaLogs or Loki), or just metrics for now? (2) What alerting channel — email, Slack, Telegram, or just Grafana alerting with no external notification?

**Answer:** Metrics + VictoriaLogs. Deploy VictoriaLogs alongside VictoriaMetrics for centralized log collection from the start.

**Follow-up — alerting channel:**

**Question:** For alerting notifications — when VictoriaMetrics detects a problem (node down, disk full, K8s pod crash-looping, etc.), where should alerts be sent?

**Answer:** Ntfy (self-hosted push notification service). No dependency on third-party platforms. Mobile + desktop apps available.

---

## Q7 — VM/LXC placement across nodes

**Question:** Let's nail down the VM/LXC placement across nodes based on each node's strengths.

**Answer (after iterating on disk constraints and K8s sizing):**

Revised placement with security lab on pve0 (disk-rich) and bumped K8s workers (Option C — 96GB total):

**pve0-nic0 (128GB RAM, 4TB SSD, 42TB HDD) — Infrastructure + Security:**
- Infra LXCs: step-ca, kanidm, victoria-metrics, victoria-logs, grafana, ntfy, gitea, homepage
- K8s: 1 control plane (4GB) + 2 workers (2 × 20GB / 6 cores = 40GB)
- Security lab: BlackArch (8GB/50GB), REMnux (8GB/100GB), future OSINT VMs
- RAM: ~87GB used, ~41GB headroom
- Disk: SSD for VM OS disks, HDD for data + security tools + backups

**pve2 (82GB RAM, 1TB SSD, 4TB ZFS, RTX 2080 Ti) — Primary AI:**
- K8s: 1 control plane (4GB) + 2 workers (2 × 16GB / 4 cores = 32GB)
- AI GPU VM: 24GB RAM, 8 cores, 2080 Ti passthrough (11GB VRAM)
- RAM: ~64GB used, ~18GB headroom (ZFS ARC gets ~16GB for NFS caching)
- Disk: 1TB SSD for VMs, 4TB ZFS for AI models/datasets (NFS-exportable)
- Note: AI VM reduced from 32GB to 24GB — 11GB VRAM is the real bottleneck for model size; host RAM freed for ZFS ARC

**pve3 (64GB RAM, 256GB SSD, RTX 2060) — Secondary AI:**
- K8s: 1 control plane (4GB) + 2 workers (2 × 12GB / 4 cores = 24GB)
- AI GPU VM: 16GB RAM, 2060 passthrough (6GB VRAM)
- RAM: ~48GB used, ~16GB headroom
- Disk: ~100GB used, ~130GB free (models via NFS from pve2)

---

## Q5 — Authentication / SSO

**Question:** For authentication/SSO, I'm recommending Authentik in an LXC on pve0. It would provide OIDC/OAuth2 login for Proxmox, Gitea, Grafana, and Kubernetes (via Talos OIDC config on the API server). This means one set of credentials across all services. Do you have any existing identity providers or preferences? And should it also integrate with Tailscale identity, or keep them separate?

**Answer:** Use Kanidm instead of Authentik. Kanidm is a Rust-based identity management server with native OIDC/OAuth2, LDAP, WebAuthn/passkey support, and built-in MFA. Lower resource footprint.

---

## Q8 — pve2 RAM balance (ZFS ARC)

**Question:** pve2 is at ~72GB used out of 82GB with only ~10GB left. ZFS uses ARC for read caching and starving it hurts performance, especially for NFS model serving. Drop AI GPU VM to 24GB or drop K8s workers to 12GB each?

**Answer:** Smaller AI VM (24GB instead of 32GB). 11GB VRAM is the real bottleneck for model size anyway — host RAM freed for ZFS ARC.

---

## Q9 — Kubernetes namespace structure and ingress

**Question:** Namespace layout: kube-system, cert-manager, ingress, monitoring, prod, staging, dev, ai. Isolation via NetworkPolicies, ResourceQuotas, RBAC tied to Kanidm OIDC. Preference for ingress controller?

**Answer:** Cilium with Gateway API. Replaces Flannel as CNI and serves as the ingress layer. eBPF-based networking, native Gateway API support, more powerful network policies. No separate ingress controller needed. Talos config must disable default Flannel CNI.

Updated namespace list (no separate `ingress` namespace):
- kube-system, cert-manager, monitoring, prod, staging, dev, ai
- Cilium runs in kube-system

---

## Q14 — Tailscale ACLs, access control, and PAW / NixOS machine roles

**Question:** For Tailscale access control — proposed access matrix. Also, the two unused NixOS machines should be repurposed following the ANSSI PAW (Privileged Access Workstation) framework.

**Answer:** Approved access model:

- **Lenovo (8GB, NixOS) — PAW:** Hardened NixOS, only admin tools (talosctl, kubectl, tofu, ansible, ssh). No browser, no email. Kanidm MFA-enforced admin account. Full infrastructure access via Tailscale. Used for: Proxmox management, K8s administration, Ansible runs, emergency access. 8GB is sufficient for CLI-only admin work.
- **Dell Inspiron (i5, 32GB, NixOS) — Backup / DR node:** Off-cluster backup target. Storage: 512GB SSD + 2TB HDD (chassis) + 12TB USB drive = ~14.5TB total. Runs backup services (restic/borgmatic). Holds replicas of critical data: Gitea repos, VictoriaMetrics data, Talos etcd snapshots, infrastructure state.
- **ThinkPad (Qubes)** → Development + operational use. Access to: services, AI, dev tools, Gitea. Privileged admin operations go through the PAW.
- **MacBook Air** → Service access only: Homepage, Grafana, Gitea, Open WebUI. No Proxmox/K8s/security lab.
- **Mac Mini** → Minimal: Homepage, Open WebUI only.
- All devices → DNS resolution of homelab.internal via Tailscale split DNS.

---

## Q18 — Proxmox management IPs

**Question:** Current Proxmox host IPs vs target scheme (.2/.3/.4). Should we migrate?

**Answer:** Keep current PVE IPs for now (pve0=.10, pve2=.2, pve3=.3). Add as a TODO to adjust to .2/.3/.4 scheme once physical access to the homelab is available. Too risky to change remotely — requires corosync/cluster reconfiguration.

---

## Q19 — Implementation phasing

**Question:** Should the spec include a recommended implementation order?

**Answer:** No. Document the target state only. Implementation order will be decided at build time.

---

## Q17 — Final IP allocation table

**Question:** Confirm the full IP allocation for the clean migration.

**Answer:** Approved. Full allocation:

```
10.0.0.1          pfSense gateway
10.0.0.2          pve0-nic0 (management)
10.0.0.3          pve2 (management)
10.0.0.4          pve3 (management)
10.0.0.5-9        Reserved (future Proxmox nodes)
10.0.0.10         step-ca
10.0.0.11         kanidm
10.0.0.12         victoria-metrics
10.0.0.13         grafana
10.0.0.14         gitea
10.0.0.15         homepage
10.0.0.16         victoria-logs
10.0.0.17         ntfy
10.0.0.18-19      Reserved (future infra)
10.0.0.20         K8s cluster 1 API VIP
10.0.0.21-23      K8s cluster 1 control planes
10.0.0.24-29      Reserved (future clusters)
10.0.0.31-36      K8s cluster 1 workers
10.0.0.37-49      Reserved (future workers)
10.0.0.51         ai-gpu-1 (pve2, 2080 Ti)
10.0.0.52         ai-gpu-2 (pve3, 2060)
10.0.0.53-59      Reserved (future AI/ML)
10.0.0.61         blackarch
10.0.0.62         remnux
10.0.0.63-79      Reserved (future security lab)
10.0.0.80-99      Reserved (future services)
10.0.0.100-199    DHCP pool
10.0.0.200-254    Reserved
```

---

## Q16 — VMID and MAC scheme (scale-out)

**Question:** The current 4-digit VMID scheme (NCCI) limits to 10 instances per category per node and has no cluster identifier for multi-cluster growth. Should we adopt a 5-digit scheme?

**Answer:** Adopt 5-digit VMID scheme (NCCII) for multi-cluster scale-out.

VMID format: NCCII (5 digits)
- N = Proxmox node (1-9): 1=pve0, 2=pve2, 3=pve3
- CC = Category (cluster-aware):
  - 01-09: Infrastructure services
  - 10: K8s cluster 1 — control planes
  - 11: K8s cluster 1 — workers
  - 20/21: K8s cluster 2 (control/worker)
  - 30/31: K8s cluster 3 (and so on)
  - 50: AI/ML
  - 60: Security lab
  - 90: Templates
- II = Instance (01-99)

MAC format: BC:24:13:5F:39:XY
- X = Category: A=infrastructure, D=K8s control, E=K8s worker, F=AI/ML, B=security lab
- Y = Instance: 0-F (hex)

Examples:
- 10101 = pve0, infra, step-ca
- 11001 = pve0, K8s-1 control, 01
- 11101 = pve0, K8s-1 worker, 01
- 25001 = pve2, AI/ML, 01
- 16001 = pve0, security, 01

Scales to: 9 Proxmox nodes, 9+ K8s clusters, 99 instances per category per node.

---

## Q15 — Backup strategy

**Question:** Backup strategy for the Dell Inspiron — what data, what tools, offsite or local only?

**Answer:** Design later. Keep as a TODO. Backup targets identified but need more thought, especially since Qubes OS backups and other data sources need to be considered holistically.

Identified backup targets (for future design):
- Gitea repos + database, VictoriaMetrics/Logs data, Talos etcd snapshots, Kanidm database, step-ca PKI, Terraform state/Talos secrets, Qubes OS backups
- Dell Inspiron storage: 512GB SSD (OS/cache), 2TB HDD (primary), 12TB USB (secondary)

---

## Q13 — Security lab scope

**Question:** For the security lab / OSINT / pentesting setup on pve0 — what additional capabilities do you need beyond BlackArch and REMnux?

**Answer:** Current setup is enough. BlackArch + REMnux covers pentest and malware analysis needs. Additional VMs (OSINT, target VMs, network analysis) can be added later as needed.

---

## Q12 — Gitea role and git workflow

**Question:** For Gitea — it's currently in an LXC on Proxmox. What role should it play alongside GitHub and sys-git on Qubes?

**Answer:** Three-tier git architecture:
1. **GitHub** — Source of truth, authoritative remote, public CI (GitHub Actions)
2. **sys-git (Qubes)** — Inter-qube middleman for dev-qube ↔ infra-admin communication and extra backup
3. **Gitea** — Mirrors FROM GitHub (read-only), runs local CI/CD via Gitea Actions with K8s-based runners

Gitea Actions benefits: pipelines can test against the actual K8s cluster, run `tofu plan` against real Proxmox, validate Ansible playbooks — things GitHub Actions can't do without exposing infrastructure.

Gitea Actions ~85-90% compatible with GitHub Actions (same YAML syntax, most marketplace actions work). Same workflow files can often run on both platforms with minor conditionals.

---

## Q11 — AI/ML software stack

**Question:** What software stack do you want on the GPU VMs for the full ML pipeline?

**Answer:** Approved stack:

**Primary GPU VM (pve2, 2080 Ti, 11GB VRAM, 24GB RAM):**
- NVIDIA drivers + CUDA toolkit
- Ollama for LLM inference (serves models via API) — runs large models (7B-13B quantized)
- Open WebUI for chat interface
- MLflow for experiment tracking
- Python + PyTorch for training/fine-tuning

**Secondary GPU VM (pve3, 2060, 6GB VRAM, 16GB RAM):**
- NVIDIA drivers + CUDA
- Ollama (smaller/specialized models: embeddings for RAG, Whisper, small coding models)
- Batch fine-tuning jobs that would block primary from serving inference

Two independent GPU VMs with different roles. Clients choose which Ollama endpoint to hit based on model needs. Models stored on pve2 4TB ZFS, shared to pve3 via NFS. K8s `ai` namespace runs orchestration (model registry, job scheduling) while GPU compute stays on dedicated VMs.

---

## Q10 — Qubes OS integration with homelab

**Question:** For the Qubes OS integration — your ThinkPad is the primary technical workstation for DevOps, AI, and development. How should the ThinkPad connect to and manage the homelab infrastructure?

**Answer:** Approved mapping:
- sys-tailscale qube → provides network access to 10.0.0.0/24 via Tailscale subnet routing
- A dedicated "infra-admin" AppVM (or reuse ansible qube) with: talosctl, kubectl, tofu, ansible → manages the Proxmox cluster and K8s
- dev qube → development work, pushes to Gitea
- A dedicated "osint" AppVM → connects to OSINT VMs on pve0 or runs lightweight OSINT tools locally
- disp-pentest DispVM → ephemeral pentesting sessions, connects to BlackArch/REMnux via Tailscale

---

## Q4 — DNS resolver setup

**Question:** For DNS resolution of homelab.internal: pfSense has a built-in DNS Resolver (Unbound). The plan would be to configure host overrides there so that grafana.homelab.internal → 10.0.0.13, gitea.homelab.internal → 10.0.0.14, etc. Tailscale clients would need to use pfSense as their DNS server (via Tailscale's DNS settings or split DNS) to resolve these names remotely. Are you already using pfSense's DNS Resolver for your LAN, or is DNS handled elsewhere (e.g., PiHole, Cloudflare directly on clients)?

**Answer:** Not using it yet, but down the line I want to use PiHole. Clients currently point to external DNS. Will need to switch LAN DNS to pfSense initially, with PiHole planned as a future addition.

---

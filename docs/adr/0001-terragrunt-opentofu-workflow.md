# ADR 0001: Terragrunt-based OpenTofu workflow for the homelab repo

## Status

Accepted &mdash; 2026-04-26.

## Table of Contents

*   [Context](#context)
*   [Decision Summary](#decision-summary)
*   [Decisions](#decisions)
    *   [1. Adopt Terragrunt as the OpenTofu workflow layer](#1-adopt-terragrunt-as-the-opentofu-workflow-layer)
    *   [2. Single repository: extend the existing homelab monorepo](#2-single-repository-extend-the-existing-homelab-monorepo)
    *   [3. State backend: reuse the existing MinIO instance](#3-state-backend-reuse-the-existing-minio-instance)
    *   [4. Modules: vendor as maintained forks](#4-modules-vendor-as-maintained-forks)
    *   [5. Providers: upstream registries; fork only when patching](#5-providers-upstream-registries-fork-only-when-patching)
    *   [6. Lightest viable runtime](#6-lightest-viable-runtime)
    *   [7. One Terragrunt unit per cluster](#7-one-terragrunt-unit-per-cluster)
    *   [8. One Terragrunt unit per LXC](#8-one-terragrunt-unit-per-lxc)
    *   [9. One Terragrunt unit per standalone VM](#9-one-terragrunt-unit-per-standalone-vm)
    *   [10. Flat L2 today; VLAN segmentation by purpose as the target](#10-flat-l2-today-vlan-segmentation-by-purpose-as-the-target)
    *   [11. Secrets: vault qube + KeePassXC + qrexec](#11-secrets-vault-qube--keepassxc--qrexec)
    *   [12. Pre-commit scope: language-agnostic only](#12-pre-commit-scope-language-agnostic-only)
    *   [13. CI runner: Gitea Actions on idols-aquamarine](#13-ci-runner-gitea-actions-on-idols-aquamarine)
    *   [14. Ansible: folded into the cluster module](#14-ansible-folded-into-the-cluster-module)
    *   [15. Kubeconfig: per-cluster file plus merged contexts](#15-kubeconfig-per-cluster-file-plus-merged-contexts)
*   [Target Repository Layout](#target-repository-layout)
*   [Migration Path](#migration-path)
*   [Consequences](#consequences)
*   [Out of Scope](#out-of-scope)
*   [Open Questions](#open-questions)

## Context

The homelab currently manages OpenTofu state for two scopes: Kubernetes
cluster bootstrap (`ha-k8s-proxmox/terraform/`) and a Gitea instance
(`gitea/`). Each is a single flat module with its own state and providers.

The growth plan invalidates that shape:

*   Two to three Kubernetes clusters on Proxmox.
*   Multiple LXC-hosted services (Gitea exists; homelab LXC exists; more
    planned).
*   Multiple standalone VMs for security, OSINT, and AI work (BlackArch
    and remnux exist today; a Windows VM is planned; a GPU-passthrough VM
    already exists).
*   The existing GitHub organization, already managed in a separate repo
    (`terragrunt-github-org`) and out of scope for this ADR.

A single flat module per workload does not scale across N clusters,
N containers, and N VMs without copy-paste duplication of backend,
provider, and boilerplate configuration. The choice is whether to absorb
the cost of adopting a workflow layer now, while there is one cluster and
a small fleet, or later under load with more state to migrate.

The `terragrunt-github-org` repo already demonstrates the pattern at scale
for GitHub resources: per-resource leaf units, shared `_common/` templates,
hierarchical configuration. The same pattern fits Talos clusters,
single-purpose LXC containers, and standalone VMs, with one important
constraint about coupling
(see [decision 7](#7-one-terragrunt-unit-per-cluster) and
[decision 9](#9-one-terragrunt-unit-per-standalone-vm)).

## Decision Summary

| #  | Decision                                                              |
|----|-----------------------------------------------------------------------|
| 1  | Adopt Terragrunt as the OpenTofu workflow layer.                      |
| 2  | Extend the existing homelab monorepo; do not create a new repo.       |
| 3  | Reuse the existing MinIO instance (`minio.writefor.fun`) for state.   |
| 4  | Vendor modules as maintained forks under the user's Gitea org.        |
| 5  | Source providers from upstream registries; fork only when patching.   |
| 6  | Lightest viable runtime as a workload-placement principle.            |
| 7  | One Terragrunt unit per cluster, not per VM.                          |
| 8  | One Terragrunt unit per LXC container.                                |
| 9  | One Terragrunt unit per standalone VM; coupled groups are one unit.   |
| 10 | Flat L2 today; VLAN segmentation by purpose is the planned target.    |
| 11 | Secrets in vault qube (KeePassXC); transferred via Qubes RPC.         |
| 12 | Pre-commit runs only language-agnostic hooks; no `tofu`/`terragrunt`. |
| 13 | Gitea Actions runner on `idols-aquamarine`.                           |
| 14 | Fold `ansible/install.yaml` into the Talos cluster module.            |
| 15 | Write each cluster's kubeconfig to a known path; merge contexts.      |

## Decisions

### 1. Adopt Terragrunt as the OpenTofu workflow layer

Use [Terragrunt](https://terragrunt.gruntwork.io/) as a thin wrapper around
OpenTofu. Each leaf unit (`live/<scope>/<name>/terragrunt.hcl`) inherits
backend, provider, and module configuration from a hierarchy of `*.hcl`
files at the repo root and `_common/`.

**Rationale.** Terragrunt earns its keep when there are many similar
deployable units sharing infrastructure plumbing. Three clusters plus a
growing fleet of LXCs and VMs cross that threshold. The alternative
(N copy-pasted Tofu modules) breaks down by the second cluster.

**Scope.** Terragrunt is the workflow layer for OpenTofu work only. NixOS,
Qubes, Talos patches, and any retained Ansible continue using their
existing tools, per `docs/DESIGN.md` ("platform-native tooling").

### 2. Single repository: extend the existing homelab monorepo

Add the Terragrunt structure to the existing homelab repo alongside the
current submodules and subprojects. Do not create a separate
`tg-homelab-infra` repo.

**Rationale.** The repo already partitions by platform. MinIO bucket
bootstrap already lives in `nixos-config/infra/minio/tf-s3-backend/`.
Splitting state across repos would scatter related infrastructure
(cluster &harr; addon &harr; DNS) into separate places without isolation
benefits.

### 3. State backend: reuse the existing MinIO instance

Configure `root.hcl` to use the `s3` backend with custom endpoints pointing
at the existing MinIO at `minio.writefor.fun`. Use the bootstrap pattern
already established in `nixos-config/infra/minio/tf-s3-backend/` to
provision the state bucket.

**Rationale.** MinIO is already deployed (NixOS, behind Caddy, used by
Loki). Adding a new backend service is unjustified.

**Bootstrap.** The MinIO host itself is **not** managed by this Terragrunt
tree. It is bootstrapped via NixOS independently, which sidesteps the
chicken-and-egg of state-storing-the-thing-that-stores-state.

### 4. Modules: vendor as maintained forks

Source modules from forks the user maintains, hosted on the homelab Gitea
instance. Pin via git tag in `terraform.source` URLs, e.g.:

```
git::https://gitea.example/user/terraform-talos-cluster.git?ref=v0.1.0
```

A single forks-monorepo (`tg-modules` with subdirectory `source`
references) is preferred over one repo per module, for fewer release
flows.

**Active forks include**, as of writing:

*   GitHub organization, repository, and team modules.
*   Talos cluster module(s).
*   Proxmox VM and LXC module(s).

### 5. Providers: upstream registries; fork only when patching

Pull providers (`bpg/proxmox`, `siderolabs/talos`, `integrations/github`,
`aminueza/minio`) from the public OpenTofu registry. Fork only when a
specific patch is required, in which case the fork is published as a
provider binary mirror or referenced via `dev_overrides`.

**Rationale.** Provider maintenance is heavier than module maintenance.
Track upstream by default; carry patches only when forced.

### 6. Lightest viable runtime

Workload-runtime selection follows a "lightest viable runtime" rule.
Prefer Docker/Compose &rarr; LXC &rarr; VM &rarr; cluster workload, in
that order. Step up only when the lighter option is functionally
inadequate (kernel modules, GPU/USB passthrough, full-OS isolation,
distinct kernel, Windows, sustained multi-host scheduling).

The Terragrunt resource category (`live/clusters/`, `live/lxc/`,
`live/vms/`) reflects the runtime needed at provisioning time, not a
permanent classification. A workload may move between categories as
requirements change; doing so is a migration between leaf units, not a
restructure of the tree.

**Rationale.** Stated minimalism preference. Each step up the runtime
ladder adds resource overhead, configuration surface, and operational
weight. Defaulting to the lightest option keeps the homelab maintainable
by one person.

This principle informs the existence of decisions 7, 8, and 9 as separate
categories.

### 7. One Terragrunt unit per cluster

Each Kubernetes cluster is a single Terragrunt unit at
`live/clusters/<name>/`. The unit consumes a `talos-cluster` module that
encapsulates the entire VMs &rarr; Talos secrets &rarr; bootstrap &rarr;
kubeconfig graph.

**Rationale.** A Talos cluster's resources are tightly coupled
(`talos_machine_secrets` shared across nodes, bootstrap depends on control
planes, kubeconfig is a cluster-level output). Splitting per VM would
force `dependency` blocks for every IP and bootstrap step, against the
resource graph rather than with it.

### 8. One Terragrunt unit per LXC

Each single-purpose LXC is a single Terragrunt unit at `live/lxc/<name>/`.
The container name derives from the directory name. The unit consumes a
generic `lxc-container` module.

**Rationale.** Single-purpose LXCs are genuinely independent (no shared
state, no cross-container runtime coupling at the OpenTofu layer), so
"one unit per resource" applies cleanly.

### 9. One Terragrunt unit per standalone VM

Each independent Proxmox VM is a single Terragrunt unit at
`live/vms/<name>/`. The unit consumes one parameterized `proxmox-vm`
module that supports:

*   Cloud-init Linux images and ISO-installed OSes (e.g. Windows).
*   Optional PCI passthrough (GPU, capture cards).
*   Optional USB passthrough (hardware tokens, dongles).
*   Per-VM CPU, memory, and disk profiles.

Do not pre-emptively split into `linux-vm` / `windows-vm` / `gpu-vm`
submodules. One module with optional inputs is lighter to maintain.

**Coupled groups.** If a future workload requires multiple VMs that share
state, secrets, or bootstrap ordering (HA pairs with a virtual IP, an
N-node Ceph or etcd cluster, a database with replication), that group is
modeled as a *single* Terragrunt unit at `live/vms/<group-name>/` whose
module produces N VMs internally &mdash; same shape as the Talos cluster
decision. The structural test: if a single VM in the group can be
re-rolled or destroyed without touching its peers, it is independent and
gets its own unit; otherwise the group is the unit.

**Current and planned VMs are all independent:** BlackArch, remnux,
Windows, OSINT, security, AI workstations.

### 10. Flat L2 today; VLAN segmentation by purpose as the target

The Proxmox L2 network is a single flat segment (`vmbr0`, no VLAN tags) on
Open vSwitch today. Per-cluster IP ranges are reserved up front in
`homelab.hcl` to prevent collisions even before the second cluster is
deployed. The Talos cluster module, the LXC module, and the Proxmox VM
module each expose `network_bridge` and `network_vlan_id` inputs so a
later split into per-VLAN bridges is an input change, not a refactor.

**Reserved IP ranges (current flat L2).**

| Range            | Purpose                                       |
|------------------|-----------------------------------------------|
| 10.0.0.50-100    | DHCP pool (fenced from static ranges).        |
| 10.0.0.139       | `ha-k8s` API VIP.                             |
| 10.0.0.140-149   | `ha-k8s` control planes.                      |
| 10.0.0.150-159   | `ha-k8s` workers.                             |
| 10.0.0.159       | `lab-k8s` API VIP.                            |
| 10.0.0.160-169   | `lab-k8s` control planes.                     |
| 10.0.0.170-179   | `lab-k8s` workers.                            |
| 10.0.0.179       | `edge-k8s` API VIP.                           |
| 10.0.0.180-189   | `edge-k8s` control planes.                    |
| 10.0.0.190-199   | `edge-k8s` workers.                           |
| 10.0.0.200-240   | LXCs and standalone VMs (static).             |
| 100.x.x.x/10     | Tailscale overlay (unchanged).                |

The `docs/DESIGN.md` network table is superseded by the table above on
acceptance of this ADR.

**Target VLAN layout (future state).** Segmentation is by purpose, not by
runtime. A service is a service whether it runs in an LXC or a small VM.

| VLAN | Purpose                                                          |
|------|------------------------------------------------------------------|
| 10   | Management / infrastructure (Proxmox, MinIO, monitoring, runner) |
| 20   | `ha-k8s` cluster                                                 |
| 30   | `lab-k8s` cluster                                                |
| 40   | `edge-k8s` cluster                                               |
| 50   | Services (LXCs, service VMs, service Docker hosts)               |
| 60   | Analysis / lab workstations (BlackArch, remnux, OSINT, AI VMs)   |
| 70   | DMZ / public-facing (when a public service appears)              |

VLAN 60 is significant given the security and OSINT workload. Those VMs
are designed to handle hostile inputs and benefit from L2 isolation from
management and services.

**Migration trigger.** The flat-to-segmented migration is initiated when
any of the following occurs first:

1.  A second Kubernetes cluster comes online.
2.  A first DMZ-public service is introduced.
3.  A first analysis VM begins handling untrusted inputs in earnest.

Naming the trigger up front prevents muddling through the moment.

**Inter-VLAN routing.** When VLANs land, an OPNsense VM provides
inter-VLAN routing and firewall enforcement. Until then, this is a
planned future VM, not a current one. The OPNsense decision is deferred
to a downstream ADR; it is named here only so the cost of the VLAN move
is not hidden.

### 11. Secrets: vault qube + KeePassXC + qrexec

Secrets (MinIO credentials, Proxmox API token, GitHub PAT, anything else
required at apply time) live in the existing vault qube
(`qubes-config/salt/vault/`). At apply time, the operator unlocks
KeePassXC in the vault qube and transfers credentials to the operations
qube via Qubes RPC (clipboard relay or `qvm-copy` for files), populating
a transient environment that dies with the qube session.

**Rationale.** Native to the existing Qubes setup; no new secrets tooling
(SOPS, age, Vault) introduced. If apply frequency rises, automate via a
`qrexec` policy exposing a `keepassxc.GetSecret`-style call &mdash; still
the same KeePassXC, no new tools.

### 12. Pre-commit scope: language-agnostic only

Pre-commit hooks (in the dev qube) run only:

*   Whitespace, EOF, large-file checks.
*   `detect-secrets` against a baseline.
*   YAML linting (`yamllint`, `prettier`).
*   Commit message linting (`gitlint`).

`tofu fmt`, `terragrunt hcl format`, `tflint`, `tofu validate`, and plan
runs are deferred to CI.

**Rationale.** Avoids installing the OpenTofu toolchain in two qubes (dev
and build/test). The dev qube stays lightweight; OpenTofu lives only
where applies happen and where the CI runner runs. The cost &mdash;
format drift caught at PR time rather than commit time &mdash; is
acceptable for a homelab.

### 13. CI runner: Gitea Actions on idols-aquamarine

Run a self-hosted Gitea Actions runner on `idols-aquamarine`. The runner
host is the same NixOS host that already serves MinIO and Caddy.

**Pipeline scope.**

*   On PR: format check, lint, validate, `terragrunt run-all plan`,
    secret scan.
*   On merge to `main`: no automatic apply. Apply remains manual from the
    build/test qube.

**Rationale.** `idols-aquamarine` is always-on, already on the homelab
network with reach to MinIO and Proxmox, and already in scope for
infrastructure use. Running CI on the workstation would gate PR feedback
on the workstation being awake.

### 14. Ansible: folded into the cluster module

Remove `ansible/install.yaml` and `ansible/tasks/` as part of the cluster
module work. The Talos provider already covers `talos_machine_secrets`,
`talos_machine_configuration_apply`, `talos_machine_bootstrap`, and
`talos_cluster_kubeconfig`. Any remaining post-bootstrap step that Ansible
currently performs is either covered by the Talos provider, moved into a
`local-exec` / `null_resource` in the cluster module, or handed off to a
GitOps tool (ArgoCD/Flux) once addons are in scope.

**Rationale.** "Fewer tools" per the stated minimalism preference. Two
orchestrators (Terragrunt dependency graph plus Ansible playbooks) for
the same bootstrap is duplication.

**Verification step.** Before deletion, audit `ansible/tasks/*.yaml` for
any operation not currently expressible in the Talos provider. Capture
findings in the migration PR; if a non-trivial gap exists, reopen this
decision.

### 15. Kubeconfig: per-cluster file plus merged contexts

Each cluster module writes its kubeconfig to a known path
(`~/.kube/configs/<cluster>.yaml`) via a `local_file` resource. A
`KUBECONFIG` env var (or shell-local merge) joins them so
`kubectl config use-context <cluster>` switches between clusters.

**Rationale.** Stable, predictable paths. Avoids ad-hoc
`terragrunt output kubeconfig` per session.

## Target Repository Layout

```
homelab/
|-- docs/
|   |-- DESIGN.md
|   `-- adr/
|       `-- 0001-terragrunt-opentofu-workflow.md   # this document
|-- nixos-config/                # submodule, unchanged
|-- qubes-config/                # submodule, unchanged
|-- root.hcl                     # backend (MinIO/s3) + provider generation
|-- homelab.hcl                  # shared vars: network ranges, Proxmox endpoint
|-- _common/
|   |-- common.hcl               # module versions, tags, defaults
|   `-- templates/
|       |-- talos-cluster.hcl
|       |-- lxc-container.hcl
|       `-- proxmox-vm.hcl
`-- live/
    |-- clusters/
    |   |-- ha-k8s/terragrunt.hcl
    |   |-- lab-k8s/terragrunt.hcl
    |   `-- edge-k8s/terragrunt.hcl
    |-- lxc/
    |   |-- gitea/terragrunt.hcl
    |   `-- homelab/terragrunt.hcl
    `-- vms/
        |-- blackarch/terragrunt.hcl
        |-- remnux/terragrunt.hcl
        `-- <future-vms>/terragrunt.hcl
```

The directories `ha-k8s-proxmox/` and `gitea/` are removed once their
contents have migrated into the `live/` tree.

Modules live in a separate Gitea-hosted repo (decision 4); they are not
checked into the homelab repo.

## Migration Path

Ordered to keep existing workloads operational throughout.

1.  **Decision record + scaffolding.** This ADR. Add `root.hcl`,
    `homelab.hcl`, `_common/common.hcl` skeletons. No `live/` units yet.
    Verify `terragrunt --help` from the build/test qube.
2.  **State backend bootstrap.** Reuse
    `nixos-config/infra/minio/tf-s3-backend/` to ensure the
    `tg-homelab-tfstate` bucket exists. Confirm S3 endpoints in
    `root.hcl` resolve.
3.  **First module: `talos-cluster`.** Refactor
    `ha-k8s-proxmox/terraform/*.tf` into a module hosted on Gitea. Tag
    `v0.1.0`. Audit `ansible/install.yaml` per decision 14; capture any
    gaps in the module.
4.  **First Terragrunt unit: `live/clusters/ha-k8s/`.** Point at the new
    module. **Import existing state** rather than recreating the cluster.
    Verify a no-op plan.
5.  **Remove `ha-k8s-proxmox/`.** After the new unit is the source of
    truth, delete the old directory. Update root README.
6.  **First LXC migration: `gitea`.** Smaller blast radius than the
    cluster; validates the LXC pattern. Tag an `lxc-container` module
    `v0.1.0`. Migrate `gitea/` to `live/lxc/gitea/`.
7.  **Second LXC: `homelab`.** Same module, new unit.
8.  **CI runner.** Configure Gitea Actions runner on `idols-aquamarine`
    via NixOS. Wire PR pipeline (fmt, lint, validate, plan). No apply
    automation.
9.  **Pre-commit hooks.** Install language-agnostic hooks per decision
    12.
10. **First standalone VM: `blackarch`.** Tag a `proxmox-vm` module
    `v0.1.0`. Migrate `blackarch` to `live/vms/blackarch/`. Smaller
    blast radius than `remnux` if a re-roll is needed during pattern
    shake-out.
11. **Second standalone VM: `remnux`.** Same module, new unit. Add the
    GPU-passthrough VM as a third unit, exercising the PCI-passthrough
    input path of the module.
12. **Second cluster: `lab-k8s`.** Proves multi-cluster works
    end-to-end. Validate context switching per decision 15.
13. **Third cluster: `edge-k8s`.** When ready.

Each step is independently revertible until the previous directory is
deleted.

## Consequences

### Positive

*   N>1 clusters, LXCs, and VMs share backend, provider, naming, and
    tagging configuration without copy-paste.
*   State per leaf unit reduces blast radius: a cluster apply cannot
    affect an LXC's state, and vice versa.
*   Adding a fourth cluster, a fifth LXC, or a tenth VM is a `cp -r`
    plus minor edits.
*   Single OpenTofu install on the homelab side (build/test qube). CI
    runner shares that toolchain on `idols-aquamarine`.
*   Ansible is removed; one fewer tool to maintain.
*   Existing MinIO, vault qube, and Gitea infrastructure is reused; no
    new services introduced.
*   Per-cluster IP ranges are reserved before they are needed; no
    collision migration when the second cluster lands.
*   Network modules accept VLAN inputs from day one, so the future move
    to segmented L2 is a parameter change.

### Negative / accepted costs

*   Terragrunt is an additional tool layer not previously required. The
    learning and maintenance cost is amortized over the planned scale,
    not justified by the current scale alone.
*   `tofu fmt` drift is caught at PR time, not commit time. Acceptable.
*   The cluster module must replicate any non-Terraform-expressible step
    in `ansible/install.yaml`. If such a step exists and cannot be
    folded in, decision 14 is revisited.
*   State migration (importing existing cluster and Gitea state into
    Terragrunt) is the riskiest single category of step. A failed
    import means rebuilding the resource from secrets and config, which
    is recoverable but disruptive.
*   The `proxmox-vm` module must absorb several optional code paths
    (cloud-init vs ISO, with/without PCI/USB passthrough). Module
    complexity grows with each new VM that exercises a new code path.

## Out of Scope

The following are deferred to later ADRs.

*   Kubernetes addon management (cert-manager, ingress, ArgoCD/Flux).
    Probably platform-native (GitOps) rather than OpenTofu, per
    `docs/DESIGN.md`.
*   NixOS host configuration management (a planned redesign of the Nix
    setup is out of scope here).
*   macOS (`darwin`) hosts.
*   Multi-Proxmox-node clustering, if/when a second Proxmox host comes
    online.
*   Backup and disaster recovery for MinIO state.
*   Provider-fork distribution mechanism (binary mirror vs.
    `dev_overrides`); decided when first patched provider is needed.
*   OPNsense VM and inter-VLAN routing/firewall configuration; decided
    when the VLAN migration trigger fires (decision 10).

## Open Questions

*   **Idle workload placement.** The user has additional always-on or
    semi-always-on NixOS hosts (Dell Inspiron, small Lenovo) beyond
    `idols-aquamarine`. Future workloads (a second runner, a backup
    MinIO target, a build cache) may land on these. Tracked here as
    available capacity, not a current decision.
*   **Single-tenant vs. multi-tenant clusters.** Whether `lab-k8s` and
    `edge-k8s` differ in purpose (per-environment vs. per-experiment vs.
    per-edge-site) shapes their addon and policy choices. Not required
    for the structural decisions in this ADR.

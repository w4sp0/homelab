# LXC Containers

Self-hosted Gitea LXC on Proxmox. Read-only mirror of GitHub repositories,
reachable over Tailscale.

## Table of Contents

*   [Description](#description)
*   [Architecture](#architecture)
*   [Design Decisions](#design-decisions)
*   [Prerequisites](#prerequisites)
*   [Installation](#installation)
*   [Usage](#usage)
*   [Open Questions](#open-questions)

## Description

A set of service instances ruing in a Proxmox LXC, used for a variety of
functionalities, including:

*   nextcloud
*   pihole
*   grafana + prometheus
*   homepage
*   vaultwarden
*   gitea

A Gitea instance running in a Proxmox LXC, used as a local read-only mirror
of GitHub. The instance is independent of the Kubernetes cluster: it must
remain operational while K8s is down, since it holds the manifests K8s boots
from on cold start.

The instance is reachable only over Tailscale. There is no LAN exposure and
no public ingress.

## Architecture

Three-tier replication of repository content:

```
dev qube on Qubes workstation
   |
   v
GitHub (source of truth)
   |  pull-mirror over HTTPS (Gitea-initiated, scheduled)
   v
Gitea LXC on Proxmox (homelab mirror, on tailnet)
```

**Push path.** Developer commits flow `dev qube -> GitHub`. Neither Gitea
nor sys-git is on the push path under normal operation.

**Pull path (K8s GitOps).** Flux/ArgoCD pulls from Gitea over the tailnet.
GitHub is unused at runtime once Gitea is current.

**Failure modes.**

| Down            | Effect                                                       |
|-----------------|--------------------------------------------------------------|
| GitHub          | Gitea serves last-mirrored state. Pushes blocked.            |
| Gitea           | Cluster reconciliation stops; recover or repoint Flux.       |
| GitHub + Gitea  | sys-git holds the most recently fetched copies.              |

## Design Decisions

| # | Decision                                                            |
|---|---------------------------------------------------------------------|
| 1 | Source of truth is GitHub; Gitea pull-mirrors GitHub.               |
| 2 | Network is Tailscale only; no LAN or public ingress.                |
| 3 | Git protocol is SSH; Gitea SSH access is read-only (zero-trust).    |
| 4 | sys-git on the Qubes workstation is the third-tier mirror.          |
| 5 | Two-stage Terraform: LXC provisioning, then Gitea-provider config.  |

### 1. GitHub-primary, Gitea-as-mirror

Gitea uses its built-in pull-mirror feature to fetch from GitHub on a
schedule. The mirror is one-way; Gitea is read-only in normal operation.

*Rationale.* The stated goal is local backup of repositories already
hosted on GitHub. Bidirectional or Gitea-primary topologies would add
write-path coupling without a corresponding requirement.

### 2. Tailscale-only network

The LXC joins the tailnet at first boot via a reusable, non-ephemeral auth
key with a `tag:gitea` ACL tag. Gitea's `app.ini` sets `ROOT_URL` and
`SSH_DOMAIN` to the MagicDNS hostname so clone strings shown in the UI
resolve from any tailnet client.

*Rationale.* Removes LAN exposure entirely and keeps reachability identical
from the dev qube, the workstation, and any roaming device.

### 3. SSH, read-only

The dev qube's per-qube SSH key is registered in Gitea, but Gitea's daily
role is reading. No write credentials are present in steady state.

*Rationale.* Zero-trust: the daily flow does not depend on a write
credential being available. The exceptional case (GitHub down, must commit
locally) is handled out-of-band.

### 4. sys-git as the third tier

sys-git is a Qubes qube on the workstation that runs `git fetch --mirror`
against Gitea on a schedule. It survives the loss of both GitHub and the
homelab. Its configuration is **out of scope for this Terraform** and lives
in `qubes-config/`.

### 5. Two-stage Terraform

| Stage | Provider             | Produces                                  |
|-------|----------------------|-------------------------------------------|
| 1     | `bpg/proxmox`        | LXC, cloud-init bootstrap, Gitea install. |
| 2     | `integrations/gitea` | Org, mirror repo entries, deploy keys.    |

Stage 2 consumes Stage 1 outputs (Gitea URL, admin token).

*Rationale.* The two providers operate at different layers
(infrastructure vs. application) and have a chicken-and-egg at plan time:
the Gitea provider cannot validate against an endpoint that does not yet
exist. Splitting into two units sidesteps this and gives each stage its
own state and blast radius.

## Prerequisites

*   A Proxmox node with the Debian *cloud* LXC template available. The
    standard Debian template is **not** cloud-init-aware and will not work
    with the `bpg/proxmox` `initialization` block.
*   A reusable, non-ephemeral Tailscale auth key tagged `tag:gitea`.
*   A fine-grained GitHub PAT with read access to the repositories to
    mirror.
*   Secrets staged via the vault qube; see
    [ADR 0001 decision 11](../../../docs/adr/0001-terragrunt-opentofu-workflow.md#11-secrets-vault-qube--keepassxc--qrexec).

## Installation

Two-stage apply. Stage 1 must complete before any Kubernetes cluster that
pulls manifests from Gitea is bootstrapped on a cold start. Order is
documented but not enforced by `dependency` blocks; the cluster and Gitea
are independent unit trees per
[ADR 0001 decision 7](../../../docs/adr/0001-terragrunt-opentofu-workflow.md#7-one-terragrunt-unit-per-cluster).

### Stage 1: LXC + Gitea install

```sh
terragrunt -- apply
```

Outputs the Gitea MagicDNS URL and admin token, consumed by Stage 2.

### Stage 2: Gitea content

```sh
terragrunt -- apply
```

Reads Stage 1 state, declares the org and mirror entries.

## Usage

### Steady state

*   Commit and push from the dev qube to GitHub.
*   Gitea pulls the change on its mirror schedule (default 8h; override
    per-repo as needed).
*   Flux/ArgoCD on the cluster pulls from Gitea over Tailscale.

### Kubernetes down

Gitea is unaffected. Browse, inspect history, fetch repositories from the
dev qube or sys-git as normal.

### GitHub down

Gitea continues to serve its last-mirrored state. Committing during a
GitHub outage is an exceptional path; reconcile with GitHub when it
returns.

## Open Questions

*   **Mirrored-repo list management.** Three candidates:
    1.  Static list in Stage 2 Terraform (`for_each` over a map).
    2.  Gitea "mirror everything from this GitHub user/org" via the
        `migrate` API.
    3.  A small reconciler in the LXC that lists GitHub repos and ensures
        each has a Gitea mirror entry.
    Decision deferred until Stage 2 lands.
*   **Stage 2 location.** ADR 0001 decision 8 covers LXC provisioning
    (Stage 1) under `live/lxc/<name>/` but does not place app-level
    configuration inside an LXC. Stage 2 needs a home: a sibling unit, or
    a new `live/services/<name>/` category. Decided when Stage 2 lands.

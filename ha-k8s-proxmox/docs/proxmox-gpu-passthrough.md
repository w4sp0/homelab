# Proxmox GPU Passthrough (NVIDIA) — Host Prep Runbook

Known-good procedure for configuring a Proxmox VE host to pass an NVIDIA GPU
through to a guest VM.

Validated on PVE 8.x, kernel 6.17, on both AMD Ryzen and Intel consumer platforms.

## Scope

**This runbook covers host-side preparation only** — getting the host kernel to
release the GPU and bind it to `vfio-pci` at boot. It does not cover:

- Guest VM configuration (machine type, OVMF, `hostpci`) — see separate VM runbook
- In-guest NVIDIA driver installation
- Application-layer setup (Ollama, CUDA, etc.)

## Prerequisites

- Proxmox VE 8.x (tested on kernel 6.17)
- CPU with IOMMU support (Intel VT-d or AMD-Vi) enabled in BIOS
- "Above 4G Decoding" enabled in BIOS
- NVIDIA GPU in its own IOMMU group (or sharing only with its own functions /
  the CPU root port, which is acceptable)
- Root shell access on the host (PVE web UI shell or SSH)

## Phase 1 — Pre-flight diagnostics

Run all commands on the target host as root.

### 1.1 Confirm IOMMU is active

```bash
dmesg | grep -i -e DMAR -e 'AMD-Vi' -e iommu | head -20
```

Must show IOMMU-related init lines. If empty, IOMMU is not enabled — check BIOS
settings for VT-d (Intel) / SVM + IOMMU (AMD).

### 1.2 Dump IOMMU groups

```bash
shopt -s nullglob
for g in $(find /sys/kernel/iommu_groups/* -maxdepth 0 -type d | sort -V); do
    echo "IOMMU Group ${g##*/}:"
    for d in $g/devices/*; do
        echo -e "\t$(lspci -nns ${d##*/})"
    done
done
```

The NVIDIA GPU must appear in a group that contains **only**:

- The GPU's VGA function (class `0300`)
- The GPU's HDA audio function (class `0403`)
- Optionally, USB 3.1 host controller + UCSI I²C controller
  (on cards with VirtualLink USB-C port)
- Optionally, the CPU PCIe root port (common on Intel consumer chipsets; acceptable)

**Unacceptable:** any other device (SATA, NIC, onboard USB controller) in the
same group. That situation requires the ACS override patched kernel, which is
out of scope for this runbook.

### 1.3 Record PCI information

```bash
lspci -nnks <PCI_ADDRESS>
```

Where `<PCI_ADDRESS>` is the `bus:device` from the group dump (e.g., `08:00`).

From the output, record:

- PCI domain/bus/device (e.g., `0000:08:00`)
- The four `vendor:device` IDs (VGA / HDA / USB / UCSI)
- The module name for each function (on the `Kernel modules:` line — **not**
  the driver name on `Kernel driver in use:`; they are often different)

## Phase 2 — Host configuration

### 2.1 Bootloader check

```bash
proxmox-boot-tool status
```

- If it reports valid ESP UUIDs → **systemd-boot** path
  (edit `/etc/kernel/cmdline`, run `proxmox-boot-tool refresh`)
- If it errors `proxmox-boot-uuids does not exist` → **standard GRUB** path
  (edit `/etc/default/grub`, run `update-grub`)

### 2.2 Kernel command line — add `iommu=pt`

Explicit `amd_iommu=on` / `intel_iommu=on` is usually not required on modern
kernels. `iommu=pt` should be added to put the IOMMU in passthrough mode for
non-vfio devices (performance improvement).

**GRUB path** — edit `/etc/default/grub`:

```
GRUB_CMDLINE_LINUX_DEFAULT="quiet iommu=pt"
```

Then apply:

```bash
update-grub
grep iommu /boot/grub/grub.cfg    # verify iommu=pt appears on every linux entry
```

**systemd-boot path** — edit `/etc/kernel/cmdline` (must remain a single line,
no wrapping):

```
root=/dev/mapper/pve-root ro quiet iommu=pt
```

Then apply:

```bash
proxmox-boot-tool refresh
```

### 2.3 Native module-load configuration

Create `/etc/modules-load.d/vfio.conf`:

```
vfio
vfio_iommu_type1
vfio_pci
```

> **Do not use `/etc/modules` for this.** On current PVE kernels,
> `systemd-modules-load.service` does not reliably honor `/etc/modules`.
> The native `/etc/modules-load.d/*.conf` location is the correct place.

### 2.4 vfio-pci options and loading order

Create `/etc/modprobe.d/vfio.conf`:

```
options vfio-pci ids=<VGA_ID>,<HDA_ID>,<USB_ID>,<UCSI_ID> disable_vga=1
softdep snd_hda_intel pre: vfio-pci
softdep xhci_hcd pre: vfio-pci
softdep nvidia-gpu pre: vfio-pci
```

Substitute the four `vendor:device` IDs recorded in step 1.3.

**Purpose of each line:**

- `options vfio-pci ids=...` — tells `vfio-pci` to claim any PCI device
  matching these IDs when it is loaded.
- `disable_vga=1` — prevents vfio-pci from participating in legacy VGA
  arbitration. Safe for headless hosts.
- `softdep ... pre: vfio-pci` — instructs modprobe to load `vfio-pci` before
  the named competing driver, so vfio-pci can claim the device first.

> **Important:** `softdep` keys on **module names**, not driver names. See the
> troubleshooting section for why `softdep nvidia-gpu pre: vfio-pci` does not
> cover the UCSI function — the module is `i2c_nvidia_gpu`, not `nvidia-gpu`.
> We handle that case via the blacklist in the next step.

### 2.5 Blacklist competing drivers

Create `/etc/modprobe.d/blacklist-nvidia.conf`:

```
blacklist nouveau
blacklist nvidia
blacklist nvidiafb
blacklist nvidia_drm
blacklist i2c_nvidia_gpu
```

`i2c_nvidia_gpu` provides the `nvidia-gpu` I²C driver for the USB-C UCSI
controller on NVIDIA cards with VirtualLink. It has no legitimate use on a
headless PVE host and is safe to blacklist outright. This guarantees the UCSI
function is free for vfio-pci to claim, without relying on `softdep` ordering.

### 2.6 Include vfio in initramfs

Append to `/etc/initramfs-tools/modules`:

```
vfio
vfio_iommu_type1
vfio_pci
```

This bakes vfio-pci into the initrd so it is available before userspace
drivers begin probing. Combined with `softdep` from step 2.4, this ensures
vfio-pci wins the race for the GPU's functions.

### 2.7 Rebuild initramfs

```bash
update-initramfs -u -k all
```

Expected output: one `Generating /boot/initrd.img-<version>` line per installed
kernel. PVE-specific warnings about `proxmox-boot-uuids` (on non-ZFS installs)
and `grub-efi-amd64` (meta-package not installed) are safe to ignore and
unrelated to GPU passthrough.

### 2.8 Reboot

```bash
reboot
```

Plan for ~1–2 minutes of downtime. Migrate or drain critical workloads first
if needed.

## Phase 3 — Verification

Run on the target host after reboot.

```bash
# 3.1 Cmdline applied
cat /proc/cmdline
# Expect: contains iommu=pt

# 3.2 IOMMU in passthrough mode
dmesg | grep 'iommu: Default domain type'
# Expect: Passthrough (set via kernel command line)

# 3.3 vfio modules loaded
lsmod | grep vfio
# Expect: vfio_pci, vfio_pci_core, vfio_iommu_type1, vfio, iommufd

# 3.4 ALL GPU functions bound to vfio-pci (CRITICAL)
lspci -nnks <PCI_ADDRESS>
# Expect: every function shows "Kernel driver in use: vfio-pci"

# 3.5 nouveau absent
lsmod | grep nouveau
# Expect: no output

# 3.6 Early-boot vfio-pci binding events
dmesg | grep -i vfio
# Expect: "vfio_pci: add [vendor:id...]" lines for each of the four PCI IDs
```

Success criterion: step 3.4 shows `Kernel driver in use: vfio-pci` on **every
function** of the GPU. If any function is bound to another driver, passthrough
will be unreliable — see troubleshooting.

## Recorded values (homelab)

### pve2 — AMD Ryzen 7, RTX 2080 Ti (TU102)

- PCI address: `0000:08:00`
- VGA: `10de:1e07`
- HDA: `10de:10f7`
- USB 3.1: `10de:1ad6`
- UCSI: `10de:1ad7`
- `ids=10de:1e07,10de:10f7,10de:1ad6,10de:1ad7`

### pve3 — Intel i5, RTX 2060 SUPER (TU106)

- PCI address: `0000:01:00`
- VGA: `10de:1f06`
- HDA: `10de:10f9`
- USB 3.1: `10de:1ada`
- UCSI: `10de:1adb`
- `ids=10de:1f06,10de:10f9,10de:1ada,10de:1adb`

## Troubleshooting

### Not all functions are bound to vfio-pci after reboot

1. Check `lsmod | grep vfio` — is vfio-pci loaded at all? If not, check
   `/etc/modules-load.d/vfio.conf` exists and that the initramfs rebuild ran.
2. Check `dmesg | grep vfio` — are `vfio_pci: add [...]` lines present for all
   four PCI IDs? If one is missing, there's a typo in `/etc/modprobe.d/vfio.conf`.
3. For a function stuck on another driver: look up the **module name** on the
   `Kernel modules:` line of `lspci -nnks <addr>`. Add that module name to
   `/etc/modprobe.d/blacklist-nvidia.conf`. Rebuild initramfs and reboot.

### Driver name vs module name

`lspci -nnk` displays two distinct values for each device:

- `Kernel driver in use:` — the driver's registered name
- `Kernel modules:` — the kernel module file that provides the driver

They are often, but not always, the same. The UCSI function (`08:00.3` on
TU102, `01:00.3` on TU106) is a known case where they differ: the driver
registers as `nvidia-gpu`, but the module is `i2c_nvidia_gpu`.

`softdep`, `blacklist`, and `modprobe` all operate on **module names**. When
in doubt, use the value from the `Kernel modules:` line.

### `/etc/modules` silently ignored

Confirmed on PVE 8.x with kernel 6.17: `systemd-modules-load.service` loads
`vhost_net`, `msr`, `zfs` from its default configuration but does not pick up
additions to `/etc/modules`. Use `/etc/modules-load.d/<name>.conf` instead.

### `/etc/modules-load.d/` vs `/etc/modprobe.d/`

These directories serve different purposes and are not interchangeable:

| Directory | Purpose | Content format |
|---|---|---|
| `/etc/modules-load.d/*.conf` | "Load these modules at boot" | Bare module names, one per line |
| `/etc/modprobe.d/*.conf` | "How modules behave when loaded" | `options`, `blacklist`, `softdep`, `alias` directives |

An `options` line in `modules-load.d` is silently ignored. A bare module name
in `modprobe.d` is silently ignored. Match the content to the directory.

### PVE warning: "grub-efi-amd64 meta-package not installed"

Pre-existing state on some PVE installs where the host boots UEFI but neither
`grub-efi-amd64` nor `grub-pc` was installed as the meta-package. This warning
does not affect GPU passthrough and does not block the reboot — `update-grub`
still regenerates `grub.cfg`, and the existing ESP GRUB binary reads it fine.

Fix separately with `apt install grub-efi-amd64` (side effect: `grub-install`
will run and place a new GRUB binary in the ESP — do this in isolation, not
during a passthrough bring-up).

### PVE warning: "No /etc/kernel/proxmox-boot-uuids found, skipping ESP sync"

Expected on any PVE host that was not installed on ZFS-on-root. The
`proxmox-boot-tool` mechanism is only used when `/boot` lives on the ESP; on
standard installs with a regular `/boot` filesystem, GRUB handles kernel
installation natively and this hook logs a benign skip message. Ignore.

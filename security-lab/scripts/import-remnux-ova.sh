#!/usr/bin/env bash
#
# Import REMnux qcow2 image into Proxmox VE
#
# Run this script on the target Proxmox node (pve0).
# Prerequisites: wget, qm
#
# Usage:
#   export REMNUX_QCOW2_URL='https://...'
#   ./import-remnux-ova.sh
#
set -euo pipefail

# --- Configuration ---
VMID=5001
VM_NAME="security-remnux"
TARGET_STORAGE="local-lvm"
CORES=4
MEMORY=8192
DISK_SIZE="100G"
BRIDGE="vmbr0"
WORK_DIR="/tmp/remnux-import"

# REMnux qcow2 URL — get it from https://remnux.org/#distro
QCOW2_URL="${REMNUX_QCOW2_URL:-}"

# --- Preflight checks ---
if [[ -z "${QCOW2_URL}" ]]; then
  echo "ERROR: Set REMNUX_QCOW2_URL environment variable to the qcow2 download URL."
  echo "  Get it from: https://remnux.org/#distro"
  exit 1
fi

if qm status "${VMID}" &>/dev/null; then
  echo "ERROR: VM ${VMID} already exists."
  exit 1
fi

echo "==> Creating working directory"
mkdir -p "${WORK_DIR}"
cd "${WORK_DIR}"

# --- Download qcow2 ---
echo "==> Downloading REMnux qcow2 image..."
QCOW2_FILE="${WORK_DIR}/remnux.qcow2"
if [[ ! -f "${QCOW2_FILE}" ]]; then
  wget -O "${QCOW2_FILE}" "${QCOW2_URL}"
else
  echo "    (found existing download, skipping)"
fi

# --- Create VM ---
echo "==> Creating VM ${VMID} (${VM_NAME})..."
qm create "${VMID}" \
  --name "${VM_NAME}" \
  --memory "${MEMORY}" \
  --cores "${CORES}" \
  --sockets 1 \
  --cpu host \
  --net0 "virtio,bridge=${BRIDGE}" \
  --scsihw virtio-scsi-single \
  --ostype l26 \
  --vga qxl \
  --agent 1 \
  --tags "security,remnux" \
  --description "REMnux malware analysis VM" \
  --onboot 1

# --- Import and attach disk ---
echo "==> Importing qcow2 into ${TARGET_STORAGE}..."
qm importdisk "${VMID}" "${QCOW2_FILE}" "${TARGET_STORAGE}"

echo "==> Attaching disk and configuring boot..."
qm set "${VMID}" --scsi0 "${TARGET_STORAGE}:vm-${VMID}-disk-0"
qm resize "${VMID}" scsi0 "${DISK_SIZE}"
qm set "${VMID}" --boot order=scsi0

# --- Cleanup ---
echo "==> Cleaning up temporary files..."
rm -rf "${WORK_DIR}"

echo "==> VM ${VMID} (${VM_NAME}) created successfully."

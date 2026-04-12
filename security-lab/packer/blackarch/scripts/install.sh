#!/usr/bin/env bash
set -euo pipefail

DISK="${DISK:-/dev/sda}"

echo "==> Partitioning ${DISK}"
parted -s "${DISK}" mklabel msdos
parted -s "${DISK}" mkpart primary ext4 1MiB 512MiB
parted -s "${DISK}" set 1 boot on
parted -s "${DISK}" mkpart primary ext4 512MiB 100%

echo "==> Formatting partitions"
mkfs.ext4 -F "${DISK}1"
mkfs.ext4 -F "${DISK}2"

echo "==> Mounting filesystems"
mount "${DISK}2" /mnt
mkdir -p /mnt/boot
mount "${DISK}1" /mnt/boot

echo "==> Installing base system"
pacstrap /mnt base linux linux-firmware grub openssh sudo curl wget git jq \
  python python-pip go base-devel vim qemu-guest-agent networkmanager

echo "==> Generating fstab"
genfstab -U /mnt >> /mnt/etc/fstab

echo "==> Configuring system"
arch-chroot /mnt /bin/bash <<'CHROOT'
set -euo pipefail

# Timezone and locale
ln -sf /usr/share/zoneinfo/UTC /etc/localtime
hwclock --systohc
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# Hostname
echo "blackarch" > /etc/hostname

# Network
systemctl enable NetworkManager
systemctl enable qemu-guest-agent
systemctl enable sshd

# Root password (will be changed post-deploy)
echo "root:blackarch" | chpasswd

# Bootloader
grub-install --target=i386-pc /dev/sda
grub-mkconfig -o /boot/grub/grub.cfg
CHROOT

echo "==> Base installation complete"

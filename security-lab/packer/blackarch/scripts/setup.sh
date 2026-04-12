#!/usr/bin/env bash
set -euo pipefail

echo "==> Adding BlackArch repository"
arch-chroot /mnt /bin/bash <<'CHROOT'
set -euo pipefail

# Add BlackArch repo
curl -fsSL https://blackarch.org/strap.sh -o /tmp/strap.sh
chmod +x /tmp/strap.sh
/tmp/strap.sh
rm /tmp/strap.sh

# Update package database
pacman -Syy --noconfirm

# ── Kubernetes / Cloud pentesting tools ──

echo "==> Installing tools from BlackArch repos"
pacman -S --noconfirm --needed \
  nmap \
  masscan \
  metasploit \
  john \
  nikto \
  ffuf \
  nuclei \
  trufflehog \
  gitleaks

echo "==> Installing kubectl"
curl -fsSLO "https://dl.k8s.io/release/$(curl -fsSL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
rm kubectl

echo "==> Installing trivy"
curl -fsSL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh -s -- -b /usr/local/bin

echo "==> Installing kube-hunter"
pip install --break-system-packages kube-hunter

echo "==> Installing peirates"
PEIRATES_VERSION=$(curl -fsSL https://api.github.com/repos/inguardians/peirates/releases/latest | jq -r .tag_name)
curl -fsSL "https://github.com/inguardians/peirates/releases/download/${PEIRATES_VERSION}/peirates-linux-amd64.tar.xz" -o /tmp/peirates.tar.xz
tar xf /tmp/peirates.tar.xz -C /usr/local/bin/
rm /tmp/peirates.tar.xz

echo "==> Installing kubeletctl"
KUBELETCTL_VERSION=$(curl -fsSL https://api.github.com/repos/cyberark/kubeletctl/releases/latest | jq -r .tag_name)
curl -fsSL "https://github.com/cyberark/kubeletctl/releases/download/${KUBELETCTL_VERSION}/kubeletctl_linux_amd64" -o /usr/local/bin/kubeletctl
chmod +x /usr/local/bin/kubeletctl

echo "==> Installing kube-bench"
KUBEBENCH_VERSION=$(curl -fsSL https://api.github.com/repos/aquasecurity/kube-bench/releases/latest | jq -r .tag_name)
curl -fsSL "https://github.com/aquasecurity/kube-bench/releases/download/${KUBEBENCH_VERSION}/kube-bench_${KUBEBENCH_VERSION#v}_linux_amd64.tar.gz" -o /tmp/kube-bench.tar.gz
tar xzf /tmp/kube-bench.tar.gz -C /usr/local/bin/ kube-bench
rm /tmp/kube-bench.tar.gz

echo "==> Installing kubeaudit"
KUBEAUDIT_VERSION=$(curl -fsSL https://api.github.com/repos/Shopify/kubeaudit/releases/latest | jq -r .tag_name)
curl -fsSL "https://github.com/Shopify/kubeaudit/releases/download/${KUBEAUDIT_VERSION}/kubeaudit_linux_amd64.tar.gz" -o /tmp/kubeaudit.tar.gz
tar xzf /tmp/kubeaudit.tar.gz -C /usr/local/bin/ kubeaudit
rm /tmp/kubeaudit.tar.gz

echo "==> Installing dive"
DIVE_VERSION=$(curl -fsSL https://api.github.com/repos/wagoodman/dive/releases/latest | jq -r .tag_name)
curl -fsSL "https://github.com/wagoodman/dive/releases/download/${DIVE_VERSION}/dive_${DIVE_VERSION#v}_linux_amd64.tar.gz" -o /tmp/dive.tar.gz
tar xzf /tmp/dive.tar.gz -C /usr/local/bin/ dive
rm /tmp/dive.tar.gz

echo "==> Cleaning up"
pacman -Scc --noconfirm
rm -rf /var/cache/pacman/pkg/*
CHROOT

echo "==> BlackArch setup complete"

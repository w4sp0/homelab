# Troubleshooting

Homelab troubleshooting guidelines.

## Table of Contents

*   [General approach](#general-approach)
*   [Network connectivity](#network-connectivity)
*   [Kubernetes cluster](#kubernetes-cluster)
*   [OpenTofu](#opentofu)

## General approach

1.  Search existing issues in the repository before opening a new one.
2.  Check upstream documentation for the specific tool or platform.
3.  Isolate the problem: determine which layer is failing (network, VM,
    OS, application).

## Network connectivity

### Cannot reach VMs from workstation

The VM network (`10.0.0.0/24`) is accessed via Tailscale subnet routing.
Verify each link in the chain:

1.  **Tailscale is connected**:
    ```sh
    tailscale status
    ```

2.  **Subnet route is advertised and approved**:
    *   Check the Tailscale admin console for the Proxmox node.
    *   The route `10.0.0.0/24` must show as "Approved".

3.  **Client accepts routes**:
    *   macOS: "Use Tailscale subnets" must be enabled in preferences.
    *   CLI: `tailscale set --accept-routes`

4.  **Route exists locally**:
    ```sh
    netstat -rn | grep 10.0.0
    ```

5.  **IP forwarding on Proxmox host**:
    ```sh
    cat /proc/sys/net/ipv4/ip_forward  # must be 1
    ```

6.  **Restart Tailscale** if routes are approved but not propagating.

### VMs on different Proxmox hosts cannot reach each other

Ensure all Proxmox hosts share the same L2 network for `vmbr0`. If hosts are
on separate physical networks, configure a VLAN or overlay to bridge them.

## Kubernetes cluster

### etcd fails to form quorum

If control plane IPs change (e.g., DHCP lease expired), etcd members cannot
find each other. This is why control planes must use static IPs. Recovery
requires a full teardown and rebuild:

```sh
cd ha-k8s-proxmox/terraform
tofu destroy -var-file=values.tfvars
rm -f ../rendered/*
tofu apply -var-file=values.tfvars
cd ../ansible
ansible-playbook install.yaml
```

### VIP (10.0.0.199) not assigned

*   Verify the control plane patch uses the correct interface name (`ens18`
    for Proxmox virtio NICs).
*   VIP requires a healthy etcd cluster for leader election.
*   Check VIP status:
    ```sh
    talosctl --nodes 10.0.0.142,10.0.0.143,10.0.0.144 get addresses | grep 199
    ```

### apply-config fails with "certificate required"

The node is no longer in maintenance mode. Drop `--insecure` and use
authenticated access:

```sh
talosctl --nodes <ip> apply-config -f <config-file>
```

### apply-config fails with "config not found"

A Talos config patch file is empty or malformed. Validate the patch:

```sh
cat talos/patches/<patch-file>.yaml
```

An empty patch (`{}`) is not valid. Either remove the `--config-patch` flag
or provide a valid patch.

### Nodes show as NotReady

Nodes need time after bootstrap for the CNI (Flannel) to deploy. Wait 1-2
minutes and check again. If persisting, check kubelet logs:

```sh
talosctl --nodes <ip> logs kubelet | tail -20
```

## OpenTofu

### "Enter a value" prompt for variables

Pass the variables file:

```sh
tofu apply -var-file=values.tfvars
```

### State lock exists

If a previous run was interrupted, a lock file may remain:

```sh
tofu force-unlock <lock-id>
```

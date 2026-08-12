# Virtual Network Design

| Network | VMware type                     | Purpose                                         | Subnet                  | DHCP                                      |
| ------- | ------------------------------- | ----------------------------------------------- | ----------------------- | ----------------------------------------- |
| WAN     | `VMnet8` (NAT, built-in)        | Host internet access for pfSense's WAN leg only | Host-assigned NAT range | VMware NAT DHCP (default)                 |
| LAN     | `VMnet-LAB` (Host-only, custom) | All lab traffic                                 | `10.10.0.0/24`          | **Disabled** — pfSense is the DHCP server |

## Rules

- **Only pfSense has a NIC on `VMnet8`.** No other VM should ever be bridged to WAN or have
  internet access except through pfSense's NAT/firewall rules — this is what makes the
  firewall rules in [Security.md](../../docs/Security.md) meaningful.
- **`VMnet-LAB`'s built-in DHCP must be disabled.** If VMware's own DHCP server answers
  alongside pfSense's, clients get inconsistent addressing and DNS. `configure-vmnet.ps1`
  disables it as part of network creation; verify manually via `Edit > Virtual Network Editor`
  if you ever hand-create the network.
- **pfSense's LAN interface is `10.10.0.1/24`**, statically assigned during pfSense install
  (no DHCP client on the LAN side, obviously — it _is_ the DHCP server).

## Creating the network

```powershell
# Elevated PowerShell
workstation\scripts\configure-vmnet.ps1
```

This is idempotent — re-running it detects an existing `VMnet-LAB` mapping to `10.10.0.0/24`
and skips creation.

## Manual equivalent (GUI)

If you prefer the GUI: `Edit > Virtual Network Editor > Add Network...` → choose an unused
`VMnetN` → Host-only → uncheck "Use local DHCP service to distribute IP addresses to VMs" →
subnet `10.10.0.0`, mask `255.255.255.0` → Apply. Then rename it `VMnet-LAB` for clarity when
assigning VM NICs in the Workstation UI (VM Settings > Network Adapter > Custom: Specific
virtual network).

# Virtual Network Design

| Network | VMware type                     | Purpose                                         | Subnet                  | DHCP                                      |
| ------- | ------------------------------- | ----------------------------------------------- | ----------------------- | ----------------------------------------- |
| WAN     | `VMnet8` (NAT, built-in)        | Host internet access for pfSense's WAN leg only | Host-assigned NAT range | VMware NAT DHCP (default)                 |
| LAN     | `VMnet2` (Host-only)            | All lab traffic                                 | `10.10.0.0/24`          | **Disabled** — pfSense is the DHCP server |

## Rules

- **Only pfSense has a NIC on `VMnet8`.** No other VM should ever be bridged to WAN or have
  internet access except through pfSense's NAT/firewall rules — this is what makes the
  firewall rules in [Security.md](../../docs/Security.md) meaningful.
- **`VMnet2`'s built-in DHCP must be disabled.** If VMware's own DHCP server answers
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

The Windows CLI only accepts numbered names such as `vmnet2`; it cannot create an arbitrary
name such as `VMnet-LAB`. Re-run the script only when the selected network does not already
exist, or pass another unused number with `-VmnetName vmnetN`.

## Manual equivalent (GUI)

If you prefer the GUI: `Edit > Virtual Network Editor > Add Network...` → choose an unused
`VMnetN` → Host-only → uncheck "Use local DHCP service to distribute IP addresses to VMs" →
subnet `10.10.0.0`, mask `255.255.255.0` → Apply. Use the resulting numbered network when
assigning VM NICs in the Workstation UI (VM Settings > Network Adapter > Custom: Specific
virtual network). VMware's CLI names this network `vmnet2`; Workstation may display it as
`VMnet2`.

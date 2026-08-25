# Virtual Network Design

| Network | VMware type              | Purpose                                         | Subnet                  | DHCP                                      |
| ------- | ------------------------ | ----------------------------------------------- | ----------------------- | ----------------------------------------- |
| WAN     | `VMnet8` (NAT, built-in) | Host internet access for pfSense's WAN leg only | Host-assigned NAT range | VMware NAT DHCP (default)                 |
| LAN     | LAN Segment `LAN-LAB`    | All lab traffic                                 | `10.10.10.0/24`         | **Disabled** — pfSense is the DHCP server |

## Rules

- **Only pfSense has a NIC on `VMnet8`.** No other VM should ever be bridged to WAN or have
  internet access except through pfSense's NAT/firewall rules — this is what makes the
  firewall rules in [Security.md](../../docs/Security.md) meaningful.
- **`LAN-LAB` has no built-in DHCP service to disable.** Unlike a host-only `VMnetN`, a LAN
  Segment is a named, per-VM virtual switch with no host-adapter binding and no VMware DHCP
  service of its own — there's nothing to turn off, and no Virtual Network Editor entry to
  manage. pfSense is the only DHCP server on `LAN-LAB` by construction, not by configuration.
- **pfSense's LAN interface is `10.10.10.1/24`**, statically assigned during pfSense install
  (no DHCP client on the LAN side, obviously — it _is_ the DHCP server).

## Creating the network

There's no setup script for this — a LAN Segment doesn't need one. It's created the first time
you reference it, which happens naturally while building pfSense's second NIC (see
[`hypervisor/vms/pfsense.md`](../vms/pfsense.md)):

1. In pfSense's VM Settings, **Add... > Network Adapter**.
2. Set **Network connection** to **Custom: Specific virtual network**, open the network
   dropdown, and choose **LAN Segments... > Add...** (exact wording varies slightly by
   Workstation version and host OS — look for "LAN Segments" in the network-connection picker
   on both Windows and Linux).
3. Name it `LAN-LAB`. This creates the segment and assigns this NIC to it in one step.

Every other lab VM's NIC then picks `LAN-LAB` from the same dropdown — it already exists after
step 3 above, so there's nothing further to create for any other VM.

(This document previously described a `configure-vmnet.ps1` script wrapping VMware's
`vnetlib.exe`/`vnetlib64.exe` to create a host-only `VMnet2` network. That approach is gone —
Broadcom has confirmed `vnetlib` is broken in recent Workstation releases, and LAN Segments
need no equivalent tool at all.)

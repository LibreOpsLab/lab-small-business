# pfSense — `pfsense01`

| Spec   | Value                                        |
| ------ | -------------------------------------------- |
| vCPU   | 2                                            |
| RAM    | 2048 MB                                      |
| Disk   | 20 GB (thin)                                 |
| NIC 1  | NAT (`VMnet8`, VMware's built-in default)    |
| NIC 2  | LAN Segment `LAN-LAB`                        |
| ISO    | pfSense CE (latest stable)                   |
| LAN IP | `10.10.10.1/24` (static, set during install) |
| WAN    | DHCP from VMware NAT                         |

Built entirely by hand — no PowerShell script creates this VM or its network. This is
deliberate: it's the first VM in the lab, and building it manually is what creates `LAN-LAB`,
the LAN Segment every other VM's NIC will use.

## Build (VM + both NICs)

1. **File > New Virtual Machine**, custom hardware: 2 vCPU, 2048 MB RAM, 20 GB disk (thin
   provisioned), pfSense CE ISO attached as the CD/DVD drive.
2. **NIC 1**: leave it on Workstation's default **NAT** network connection (`VMnet8`) — this
   ships with Workstation and needs no setup.
3. **NIC 2**: VM Settings > **Add... > Network Adapter** > Network connection: **Custom:
   Specific virtual network** > open the network dropdown > **LAN Segments... > Add...** >
   name it `LAN-LAB`. This both creates the LAN Segment and assigns this NIC to it. Every other
   lab VM's NIC will pick `LAN-LAB` from the same dropdown once it exists — there's nothing
   further to create.

## Install (manual — no unattended installer available for pfSense on Workstation)

1. Boot from ISO, run the installer with the default ZFS/UFS choice (UFS is fine for a lab).
2. At "Assign Interfaces": WAN = the NIC on `VMnet8`, LAN = the NIC on `LAN-LAB`.
3. Set LAN IPv4 address to `10.10.10.1/24`. Leave LAN DHCP off for now — the next step
   configures it by hand.
4. Reboot into the installed system.

## Post-install (manual GUI configuration)

From the console or GUI (`https://10.10.10.1`), configure:

- **DHCP server (LAN)**: pool `10.10.10.100`–`10.10.10.199`, DNS server `10.10.10.10`, domain name
  `lab.internal`, gateway `10.10.10.1`.
- **DNS Resolver (Unbound)**: enabled, LAN-only access; forward `lab.internal` to `10.10.10.10`
  (Samba AD's DNS) and everything else to the WAN interface's upstream DNS — see
  [dns-architecture.md](../../diagrams/dns-architecture.md).
- **Firewall rules**: allow LAN → `10.10.10.10` (ports 53, 88, 123, 135, 137-139, 389, 445, 464,
  636, 3268-3269); allow LAN → `10.10.10.20` (80, 443, 587, 465, 993); allow LAN → `10.10.10.30`
  (443); block `10.10.10.30` → `10.10.10.10:389` (forces LDAPS); allow LAN → WAN (80, 443, 53,
  outbound only); default deny + log. Full rationale in
  [Security.md](../../docs/Security.md#firewall-recommendations-pfsense).

Then, optionally, run
[`pfsense/scripts/pfsense-post-install.sh`](../../pfsense/scripts/pfsense-post-install.sh) over
SSH for the package installs (`pfSense-pkg-Cron`, `pfSense-pkg-Notes`) it automates.

Once you're comfortable configuring pfSense by hand, `pfsense/config/config.xml.template`
(imported via **Diagnostics > Backup & Restore > Restore**) captures everything above as a
reviewed, reusable baseline for future rebuilds — see
[`pfsense/README.md`](../../pfsense/README.md). It's an optional shortcut for later, not where
to start.

See [docs/DeploymentGuide.md](../../docs/DeploymentGuide.md#1-pfsense--fully-manual) for the
full sequence in context.

# Vulnerability scanner — `scanner01`

Runs **Greenbone Community Edition** (OpenVAS), an open-source vulnerability scanner. Kali, and
penetration testing generally, are taught in other classes; this machine answers a different
question: *what known weaknesses does my own estate have, and did my fixes work?*

| Spec | Value                                                       |
| ---- | ----------------------------------------------------------- |
| vCPU | 2 (4 recommended by Greenbone)                              |
| RAM  | 6144 MB (Greenbone: 4 GB minimum, 8 GB recommended)         |
| Disk | 40 GB thin (Greenbone: 20 GB minimum, 60 GB recommended)    |
| NIC  | LAN Segment `LAN-LAB`                                       |
| ISO  | Ubuntu Server 24.04                                         |
| IP   | `10.10.10.60`, static (outside the DHCP pool)               |

**Where it runs.** A native VMware VM in scenario 2 (kept outside Proxmox so its memory does not
compete with the guests being scanned), a Proxmox VM in scenario 3. It is heavy, so it runs **in
the scan weeks only**: power off the Windows 11 and Linux client VMs to make room, and delete the
VM afterwards. See the [sizing table](../../scenarios/2-nested-proxmox/README.md#reference-lab-pc-and-sizing).

## Build

1. Install Ubuntu Server 24.04 by hand, then apply the [baseline](../desktop/baseline.md).
   Static address `10.10.10.60/24`, gateway `10.10.10.1`, DNS `10.10.10.10`.
2. Join the domain like any other Linux machine (`samba/scripts/join-linux-client.sh`).
3. Install Docker Engine from Docker's own apt repository (follow Docker's current Ubuntu
   instructions), then add `labadmin` to the `docker` group.
4. Fetch Greenbone's official Compose file at build time. It is not stored in this repo: it is
   third-party, it changes with each release, and Greenbone advise using the latest one.

   ```bash
   export DOWNLOAD_DIR=$HOME/greenbone-community-container
   mkdir -p "$DOWNLOAD_DIR"
   curl -f -O -L https://greenbone.github.io/docs/latest/_static/compose.yaml --output-dir "$DOWNLOAD_DIR"
   docker compose -f "$DOWNLOAD_DIR/compose.yaml" pull
   docker compose -f "$DOWNLOAD_DIR/compose.yaml" up -d
   ```

5. **Change the default password immediately.** The default login is `admin` / `admin`.

   ```bash
   docker compose -f "$DOWNLOAD_DIR/compose.yaml" exec -u gvmd gvmd gvmd --user=admin --new-password='<a strong password>'
   ```

   Wrap a password containing `$` in single quotes.
6. Wait for the vulnerability feeds to load. The first sync takes a long time (tens of minutes
   or more, depending on the connection) and scans started before it finishes are incomplete.
   Greenbone's workflow pages describe how to check progress.

## Reaching the web interface

Greenbone's Compose file publishes its web interface on the VM's loopback address only. That is
a good default, so keep it: reach it through an SSH tunnel from the admin machine instead of
opening a port.

```bash
ssh -L 9392:127.0.0.1:9392 labadmin@10.10.10.60
# then browse to the address Greenbone documents for your release, on 127.0.0.1
```

It uses a self-signed certificate. Accept it for this one tunnelled connection only; this does
not change the repo rule that the lab's own services are always verified.

## Use

Process, targets, the authorisation rules and the remediation loop:
[docs/VulnerabilityScanning.md](../../docs/VulnerabilityScanning.md).

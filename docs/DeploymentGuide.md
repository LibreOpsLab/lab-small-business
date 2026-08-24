# Deployment Guide

Follow this sequence exactly — later stages (Authentik, apps) depend on DNS and PKI from
earlier stages. Assumes VMware Workstation Pro 17+ on the host and Ubuntu Server 24.04 LTS for
all Linux VMs unless stated otherwise.

## 0. Host prerequisites

- VMware Workstation Pro installed, virtualization enabled in host BIOS.
- Ubuntu Server 24.04 LTS ISO, Windows 11 ISO, pfSense CE ISO, Ubuntu Desktop 24.04 ISO
  downloaded to the host.
- This repo ends up cloned in **two** places: once on the Windows host (to run the
  PowerShell/`vmrun` scripts from step 3 onward), and once on `linux-client01` (built in step
  2 below), which is the **control host** for everything from step 3 onward — Ansible, the PKI
  scripts, and `samba-tool` all need a real POSIX environment, and Ansible does not support
  Windows as a control node at all. Because `linux-client01` lives on the lab's own LAN
  Segment, it needs no extra networking setup to reach the other lab VMs. See
  [docs/WSLSetup.md](WSLSetup.md) only if you'd rather drive the build from WSL2 on the
  Windows host instead.
- `mkpasswd` (from the `whois` package, installed on `linux-client01` in step 2) to generate
  password hashes for the Ubuntu Server autoinstall seeds used in steps 3 and 5. No extra tool
  is needed to build the seed ISOs themselves — `workstation/scripts/build-seed-iso.ps1` uses
  IMAPI2, which ships with Windows.

## 1. pfSense — fully manual

There's no networking-setup script to run before this step — the lab's LAN Segment is created
inline while building this VM, not as a separate stage.

1. In VMware Workstation, create a new VM per
   [`workstation/vms/pfsense.md`](../workstation/vms/pfsense.md): 2 vCPU, 2 GB RAM, 20 GB disk,
   pfSense CE ISO attached.
2. NIC1: leave as VMware's default **NAT** (`VMnet8` — ships with Workstation, needs no setup).
   NIC2: **Add... > Network Adapter > Custom: Specific virtual network > LAN Segments... >
   Add...**, name it `LAN-LAB`. This is the only place `LAN-LAB` gets created — every other lab
   VM's NIC picks it from the same dropdown once it exists.
3. Install pfSense interactively (the one genuinely manual OS install in the whole lab). At
   "Assign Interfaces": WAN = the NIC on `VMnet8`, LAN = the NIC on `LAN-LAB`. Set LAN IPv4 to
   `10.10.0.1/24`; leave LAN DHCP off until the next step.
4. From the pfSense GUI (`https://10.10.0.1`), configure by hand:
   - **DHCP server (LAN)**: pool `10.10.0.100`–`10.10.0.199`, DNS server `10.10.0.10`, domain
     name `lab.internal`, gateway `10.10.0.1`.
   - **DNS Resolver (Unbound)**: enabled, LAN-only access; forward `lab.internal` to
     `10.10.0.10` (Samba AD's DNS) and everything else to the WAN interface's upstream DNS —
     see [dns-architecture.md](../diagrams/dns-architecture.md).
   - **Firewall rules**: allow LAN → `10.10.0.10` (53, 88, 123, 135, 137-139, 389, 445, 464,
     636, 3268-3269); allow LAN → `10.10.0.20` (80, 443, 587, 465, 993); allow LAN →
     `10.10.0.30` (443); block `10.10.0.30` → `10.10.0.10:389` (forces LDAPS); allow LAN → WAN
     (80, 443, 53, outbound only); default deny + log. Full rationale in
     [Security.md](Security.md#firewall-recommendations-pfsense).
5. Run [`pfsense/scripts/pfsense-post-install.sh`](../pfsense/scripts/pfsense-post-install.sh)
   over SSH for the package installs it automates (optional — see below).

Once you're comfortable with the manual flow,
[`pfsense/config/config.xml.template`](../pfsense/config/config.xml.template) (imported via
**Diagnostics > Backup & Restore > Restore**) captures everything above as a reviewed, reusable
baseline for future rebuilds — see [`pfsense/README.md`](../pfsense/README.md). It's an
optional shortcut, not where to start.

## 2. Admin desktop — `linux-client01` (control host)

This VM plays two roles: it's your **control host** for every scripted step from here on
(replacing the need for WSL2), and later — once AD exists — it also joins the domain as a lab
endpoint like any other client.

1. Create a new VM per [`workstation/vms/linux-client.md`](../workstation/vms/linux-client.md):
   2 vCPU, 4 GB RAM, 40 GB disk, single NIC on `LAN-LAB`, Ubuntu Desktop 24.04 ISO attached.
2. Install Ubuntu Desktop interactively — it gets a DHCP lease from pfSense once step 1 above
   is done.
3. Clone this repository onto it and install the tooling the rest of the guide needs:

   ```bash
   sudo apt update && sudo apt install -y ansible openssl git rsync samba-common-bin whois \
       python3 python3-pip openssh-client
   git clone <this-repo-url> ~/lab-small-business
   cd ~/lab-small-business
   ansible --version   # confirm ansible-core 2.16+
   ```

From here on, "control host" in this guide means **this VM** — every `ansible-playbook`,
`openssl`, and `samba-tool` command from step 3 onward runs from here, not from the Windows
host. (If you'd rather drive the build from WSL2 on the Windows host instead, see
[docs/WSLSetup.md](WSLSetup.md) — the LAN Segment reachability fix it documents is the only
extra step that path needs.)

## 3. Samba AD Domain Controller

1. Fill in `samba-dc01`'s install seed (see
   [`workstation/vms/samba-dc.md#autoinstall`](../workstation/vms/samba-dc.md#autoinstall) —
   copy the `.example` files, generate a password hash with `mkpasswd`).
2. `workstation/scripts/create-vms.ps1` creates `samba-dc01`'s VM shell (2 vCPU, 4 GB RAM,
   40 GB disk, static `10.10.0.10`, gateway `10.10.0.1`) and builds/attaches its seed ISO
   automatically. Boot it — Ubuntu Server installs with no prompts and reboots into a running
   system with SSH up.
3. `sudo samba/scripts/bootstrap-ad.sh` — provisions the domain (see
   [SambaAdmin.md](SambaAdmin.md)).
4. `sudo samba/scripts/create-ous.sh && sudo samba/scripts/create-groups.sh && sudo samba/scripts/create-users.sh`
5. `samba/scripts/health-check.sh` — confirm green before proceeding.

## 4. PKI bootstrap

Run from any host with `openssl` 3.x (recommended: `docker01` once it exists, or
`linux-client01` — the control host — in the interim):

```bash
cd pki/scripts
./00-init-root-ca.sh
./01-init-intermediate-ca.sh
./02-issue-server-cert.sh --cn samba-dc01.lab.internal --san "DNS:samba-dc01.lab.internal,DNS:lab.internal"
./02-issue-server-cert.sh --cn cloud.lab.internal      --san DNS:cloud.lab.internal
./02-issue-server-cert.sh --cn docs.lab.internal       --san DNS:docs.lab.internal
./02-issue-server-cert.sh --cn mail.lab.internal       --san DNS:mail.lab.internal
./02-issue-server-cert.sh --cn auth.lab.internal       --san DNS:auth.lab.internal
./02-issue-server-cert.sh --cn www.lab.internal        --san DNS:www.lab.internal
./02-issue-server-cert.sh --cn pdf.lab.internal        --san DNS:pdf.lab.internal
./02-issue-server-cert.sh --cn autoconfig.lab.internal --san DNS:autoconfig.lab.internal
```

(`make pki-init && make pki-issue-all` does the same thing.)

Move `pki/root-ca/private/ca.key.pem` to offline storage now (see [PKI.md](PKI.md)). Copy the
issued `samba-dc01.lab.internal` cert/key into `/etc/samba/tls/` on the DC and enable `tls enabled
= yes` in `smb.conf` for LDAPS (already templated in
[`samba/templates/smb.conf.j2`](../samba/templates/smb.conf.j2)).

## 5. Docker application server + Authentik

1. Fill in `docker01`'s and `authentik01`'s install seeds (same `.example`-copy-and-fill
   pattern as `samba-dc01` — see
   [`workstation/vms/docker-server.md`](../workstation/vms/docker-server.md) and
   [`workstation/vms/authentik.md`](../workstation/vms/authentik.md)), then boot them — both
   install unattended the same way `samba-dc01` did in step 3.
2. From your control host, populate `ansible/inventory/hosts.ini` (already templated with these
   IPs) and run:

   ```bash
   cd ansible
   ansible-playbook playbooks/site.yml --ask-vault-pass
   ```

   `site.yml` runs, in order: `00-common-hardening.yml`, `04-linux-client-join.yml` (for
   `docker01`/`authentik01` as domain-joined Linux hosts), `05-pki-trust.yml`,
   `02-docker-server.yml` (installs Docker Engine + brings up the reverse proxy stack), and
   `03-authentik.yml` (brings up Authentik and applies blueprints via
   [`bootstrap-authentik.sh`](../authentik/scripts/bootstrap-authentik.sh)).

3. Verify: `https://auth.lab.internal` loads with a trusted cert and you can sign in as
   `akadmin` (bootstrap credentials in `ansible/inventory/host_vars/authentik01/vault.yml`).

## 6. Applications

Still via `ansible-playbook playbooks/02-docker-server.yml --tags apps` (already included in
`site.yml`, listed separately here for iterative re-runs): brings up NextCloud, OnlyOffice,
Dovecot+Postfix, WordPress, and Stirling PDF Compose stacks under `docker/`, wired to Traefik
and to the OIDC/proxy providers created in step 5. Confirm:

- `https://cloud.lab.internal` → NextCloud, "Log in with Authentik" button present and working.
- `https://docs.lab.internal` → OnlyOffice Document Server status page.
- `mail.lab.internal:993` (IMAPS) / `:587` (submission) → see
  [docker/mail/README.md](../docker/mail/README.md) for a full send/receive test.
- `https://www.lab.internal` → WordPress, installed and ready (SSO is opt-in — see step 6a).
- `https://pdf.lab.internal` → Stirling PDF, prompts an Authentik login before showing the app
  (forward-auth, not native OIDC — see [docker/stirling-pdf/README.md](../docker/stirling-pdf/README.md)).

### 6a. Groupware apps and optional WordPress SSO

```bash
docker/nextcloud/scripts/bootstrap-nextcloud-apps.sh   # Calendar, Contacts, Talk, Mail, ONLYOFFICE connector
docker/wordpress/scripts/configure-oidc-plugin.sh       # optional: wires WordPress into Authentik SSO
```

Both are idempotent and safe to re-run. `scripts/deploy-all.sh` runs the first automatically;
the WordPress one is left manual since SSO-for-a-website is an opt-in decision, not a default.

## 7. Endpoints

`linux-client01` already exists (built manually in step 2). `win-client01`'s VM shell and
unattended Windows 11 install are handled by `workstation/scripts/create-vms.ps1` — see
[`workstation/vms/windows-client.md`](../workstation/vms/windows-client.md) for the
`autounattend.xml` setup needed before running it, then boot it once ready. What's left for
both clients is joining the domain:

1. `linux-client01`: `sudo samba/scripts/join-linux-client.sh` (joins domain, configures SSSD,
   installs the CA chain via `ansible-playbook playbooks/05-pki-trust.yml --limit
   linux-client01` or manually per [PKI.md](PKI.md)).
2. `win-client01`: confirm DNS is `10.10.0.10` (DHCP-served), then run
   [`samba/scripts/join-windows-client.ps1`](../samba/scripts/join-windows-client.ps1) elevated.
   GPOs (including CA trust) apply automatically on next `gpupdate`/reboot.
3. On each client, run the desktop app provisioning scripts — see
   [docs/DesktopApps.md](DesktopApps.md) and [`desktop-apps/`](../desktop-apps/) — to install
   NextCloud Desktop Sync, OnlyOffice Desktop Editors, Betterbird (autoconfigured), and a
   Stirling PDF app shortcut.

## 8. Validation

Run through [StudentLabManual.md](StudentLabManual.md)'s "Day 1 checklist" as an end-to-end
smoke test: domain logon from both clients, SSO into NextCloud, cert trust with no browser
warnings, mail send+receive round trip via Betterbird.

## One-shot re-runs

[`scripts/deploy-all.sh`](../scripts/deploy-all.sh) chains steps 4-6a (PKI issuance +
`ansible-playbook site.yml` + NextCloud groupware bootstrap + a post-flight `health-check.sh`
sweep) for redeploying application/identity layers onto already-created VMs — useful when
iterating without tearing down the whole lab.

## Beyond one business (optional)

Everything above is a complete, self-contained deployment on its own. If your course wants
multiple businesses, that's a separate opt-in layer under `federation/` — see
[docs/MultiBusiness.md](MultiBusiness.md) for stamping out additional independent businesses
(`scripts/provision-business.sh`) and bridging pairs of them via IPSec/VPN, or
[docs/ClassRegistry.md](ClassRegistry.md) for a classroom-wide shared CA + DNS registry so
every business is reachable with trusted HTTPS. Neither is required, and nothing above depends
on either.

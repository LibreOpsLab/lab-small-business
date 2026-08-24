# Deployment Guide

Follow this sequence exactly — later stages (Authentik, apps) depend on DNS and PKI from
earlier stages. Assumes VMware Workstation Pro 17+ on the host and Ubuntu Server 24.04 LTS for
all Linux VMs unless stated otherwise.

## 0. Host prerequisites

- VMware Workstation Pro installed, virtualization enabled in host BIOS.
- Ubuntu Server 24.04 LTS ISO, Windows 11 ISO, pfSense CE ISO, Ubuntu Desktop 24.04 ISO
  downloaded to the host.
- `ansible` (2.16+), `openssl` (3.x), and an SSH client available as the **control host** for
  everything from step 3 onward — this needs to be WSL2, not Git Bash or PowerShell alone;
  Ansible does not support Windows as a control node. See
  [docs/WSLSetup.md](WSLSetup.md) for installing WSL2, the networking fix it needs to reach
  `VMnet-LAB` (this trips up almost everyone on first try), and cloning this repository inside
  it — do that clone (not a separate Windows-side one) before continuing.
- `mkpasswd` (from the `whois` package — WSL2 has it, or any Debian/Ubuntu machine) to generate
  password hashes for the Ubuntu Server autoinstall seeds used in steps 3 and 5. No extra tool
  is needed to build the seed ISOs themselves — `workstation/scripts/build-seed-iso.ps1` uses
  IMAPI2, which ships with Windows.

## 1. Networking (VMware Workstation)

Create the two virtual networks described in
[workstation/networks/README.md](../workstation/networks/README.md) using
[`workstation/scripts/configure-vmnet.ps1`](../workstation/scripts/configure-vmnet.ps1)
(elevated PowerShell, wraps VMware's `vnetlib.exe` or `vnetlib64.exe`):

```powershell
workstation\scripts\configure-vmnet.ps1
```

This creates `VMnet8` (NAT, WAN) as-is (Workstation ships it by default) and a new host-only
`VMnet-LAB` network with **DHCP disabled** (pfSense will be the DHCP server) bound to
`10.10.0.0/24`.

## 2. pfSense

1. Create the VM per [`workstation/vms/pfsense.md`](../workstation/vms/pfsense.md) (2 vCPU,
   2 GB RAM, 20 GB disk, NIC1→VMnet8/WAN, NIC2→VMnet-LAB/LAN).
2. Install pfSense interactively (only manual-install step in the whole lab — pfSense has no
   unattended installer for Workstation). Assign WAN=NIC1, LAN=NIC2, LAN IP `10.10.0.1/24`.
3. From the pfSense console/GUI, import
   [`pfsense/config/config.xml.template`](../pfsense/config/config.xml.template)
   (`Diagnostics > Backup & Restore > Restore`) after filling in the placeholders described in
   [`pfsense/README.md`](../pfsense/README.md) (WAN type, DHCP range, DNS forwarder target).
4. Run [`pfsense/scripts/pfsense-post-install.sh`](../pfsense/scripts/pfsense-post-install.sh)
   over SSH to apply anything not expressible in `config.xml` (package installs via `pkg`,
   `pfSsh.php`-driven tweaks).

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

Run from any host with `openssl` 3.x (recommended: `docker01` once it exists, or your
workstation host in the interim):

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

1. `linux-client01`: install Ubuntu Desktop 24.04, then
   `sudo samba/scripts/join-linux-client.sh` (joins domain, configures SSSD, installs the CA
   chain via `ansible-playbook playbooks/05-pki-trust.yml --limit linux-client01` or manually
   per [PKI.md](PKI.md)).
2. `win-client01`: install Windows 11, confirm DNS is `10.10.0.10` (DHCP-served), then run
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

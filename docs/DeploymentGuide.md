# Deployment Guide

Follow this sequence exactly — later stages (Authentik, apps) depend on DNS and PKI from
earlier stages. Assumes VMware Workstation Pro 17+ on the host and Ubuntu Server 24.04 LTS for
all Linux VMs unless stated otherwise.

## 0. Host prerequisites

- VMware Workstation Pro installed, virtualization enabled in host BIOS.
- Ubuntu Server 24.04 LTS ISO, Windows 11 ISO, pfSense CE ISO, Ubuntu Desktop 24.04 ISO
  downloaded to the host.
- This repository cloned to the host, e.g. `C:\Users\<you>\Development\lab-small-business`.
- `ansible` (2.16+), `openssl` (3.x), and an SSH client available — either directly on the
  Windows host (via WSL2/Git Bash) or run from `linux-client01` once it exists (chicken-and-egg
  for the very first run, so WSL2 is recommended for stage 1-3).

## 1. Networking (VMware Workstation)

Create the two virtual networks described in
[workstation/networks/README.md](../workstation/networks/README.md) using
[`workstation/scripts/configure-vmnet.ps1`](../workstation/scripts/configure-vmnet.ps1)
(elevated PowerShell, wraps `vnetlib64.exe`):

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

1. Create `samba-dc01` per [`workstation/vms/samba-dc.md`](../workstation/vms/samba-dc.md)
   (2 vCPU, 4 GB RAM, 40 GB disk, static `10.10.0.10`, gateway `10.10.0.1`).
2. Install Ubuntu Server 24.04 (unattended install seed available at
   `workstation/vms/samba-dc.md#autoinstall`).
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
./02-issue-server-cert.sh --cn samba-dc01.lab.local --san "DNS:samba-dc01.lab.local,DNS:lab.local"
./02-issue-server-cert.sh --cn cloud.lab.local --san DNS:cloud.lab.local
./02-issue-server-cert.sh --cn docs.lab.local  --san DNS:docs.lab.local
./02-issue-server-cert.sh --cn mail.lab.local  --san DNS:mail.lab.local
./02-issue-server-cert.sh --cn auth.lab.local  --san DNS:auth.lab.local
```

Move `pki/root-ca/private/ca.key.pem` to offline storage now (see [PKI.md](PKI.md)). Copy the
issued `samba-dc01.lab.local` cert/key into `/etc/samba/tls/` on the DC and enable `tls enabled
= yes` in `smb.conf` for LDAPS (already templated in
[`samba/templates/smb.conf.j2`](../samba/templates/smb.conf.j2)).

## 5. Docker application server + Authentik

1. Create `docker01` (`10.10.0.20`) and `authentik01` (`10.10.0.30`) per
   [`workstation/vms/docker-server.md`](../workstation/vms/docker-server.md) and
   [`workstation/vms/authentik.md`](../workstation/vms/authentik.md).
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
3. Verify: `https://auth.lab.local` loads with a trusted cert and you can sign in as
   `akadmin` (bootstrap credentials in `ansible/inventory/host_vars/authentik01/vault.yml`).

## 6. Applications

Still via `ansible-playbook playbooks/02-docker-server.yml --tags apps` (already included in
`site.yml`, listed separately here for iterative re-runs): brings up NextCloud, OnlyOffice, and
Dovecot Compose stacks under `docker/`, wired to Traefik and to the OIDC clients created in step
5. Confirm:

- `https://cloud.lab.local` → NextCloud, "Log in with Authentik" button present and working.
- `https://docs.lab.local` → OnlyOffice Document Server status page.
- `mail.lab.local:993` (IMAPS) → authenticates `student01`/`lecturer01` against LDAP.

## 7. Endpoints

1. `linux-client01`: install Ubuntu Desktop 24.04, then
   `sudo samba/scripts/join-linux-client.sh` (joins domain, configures SSSD, installs the CA
   chain via `ansible-playbook playbooks/05-pki-trust.yml --limit linux-client01` or manually
   per [PKI.md](PKI.md)).
2. `win-client01`: install Windows 11, confirm DNS is `10.10.0.10` (DHCP-served), then run
   [`samba/scripts/join-windows-client.ps1`](../samba/scripts/join-windows-client.ps1) elevated.
   GPOs (including CA trust) apply automatically on next `gpupdate`/reboot.

## 8. Validation

Run through [StudentLabManual.md](StudentLabManual.md)'s "Day 1 checklist" as an end-to-end
smoke test: domain logon from both clients, SSO into NextCloud, cert trust with no browser
warnings, mail client IMAP login.

## One-shot re-runs

[`scripts/deploy-all.sh`](../scripts/deploy-all.sh) chains steps 4-8 (PKI issuance +
`ansible-playbook site.yml` + a post-flight `health-check.sh` sweep) for redeploying
application/identity layers onto already-created VMs — useful when iterating without tearing
down the whole lab.

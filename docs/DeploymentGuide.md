# Deployment Guide

Follow this sequence exactly — later stages (Authentik, apps) depend on DNS and PKI from
earlier stages. Assumes VMware Workstation Pro (Windows/Linux) or Fusion Pro (macOS) and Ubuntu
Server 24.04 LTS for all Linux VMs. Every VM is hand-built through the hypervisor's own GUI —
see [hypervisor/desktop/README.md](../hypervisor/desktop/README.md).

## 0. Host prerequisites

- This lab defaults to the `10.10.10.0/24` subnet. If that collides with your home/office
  network, or you just want a different range, run `scripts/set-subnet.sh <new-cidr>` now
  (before building any VMs) and do the rest of this guide from the resulting copy — see the
  script's header comment for usage.
- VMware Workstation Pro (Windows/Linux) or Fusion Pro (macOS) installed, virtualization enabled
  in host BIOS/firmware.
- Ubuntu Server 24.04 LTS ISO, Windows 11 ISO, pfSense CE ISO, Ubuntu Desktop 24.04 ISO
  downloaded to the host.
- `linux-client01` (built in step 2 below) is the **control host** for everything from step 3
  onward — Ansible, the PKI scripts, and `samba-tool` all need a real POSIX environment, and
  Ansible does not support Windows as a control node at all. Because `linux-client01` lives on
  the lab's own LAN Segment, it needs no extra networking setup to reach the other lab VMs. See
  [docs/WSLSetup.md](WSLSetup.md) only if you'd rather drive the build from WSL2 on a Windows
  host instead.

## 1. pfSense — fully manual

There's no networking-setup script to run before this step — the lab's LAN Segment is created
inline while building this VM, not as a separate stage.

1. In VMware Workstation/Fusion, create a new VM per
   [`hypervisor/vms/pfsense.md`](../hypervisor/vms/pfsense.md): 2 vCPU, 2 GB RAM, 20 GB disk,
   pfSense CE ISO attached.
2. NIC1: leave as VMware's default **NAT** (`VMnet8` — ships with Workstation, needs no setup).
   NIC2: **Add... > Network Adapter > Custom: Specific virtual network > LAN Segments... >
   Add...**, name it `LAN-LAB`. This is the only place `LAN-LAB` gets created — every other lab
   VM's NIC picks it from the same dropdown once it exists.
3. Install pfSense interactively (the one genuinely manual OS install in the whole lab). At
   "Assign Interfaces": WAN = the NIC on `VMnet8`, LAN = the NIC on `LAN-LAB`. Set LAN IPv4 to
   `10.10.10.1/24`; leave LAN DHCP off until the next step.
4. From the pfSense GUI (`https://10.10.10.1`), configure by hand:
   - **DHCP server (LAN)**: pool `10.10.10.100`–`10.10.10.199`, DNS server `10.10.10.10`, domain
     name `lab.internal`, gateway `10.10.10.1`.
   - **DNS Resolver (Unbound)**: enabled, LAN-only access; forward `lab.internal` to
     `10.10.10.10` (Samba AD's DNS) and everything else to the WAN interface's upstream DNS —
     see [dns-architecture.md](../diagrams/dns-architecture.md).
   - **Firewall rules**: allow LAN → `10.10.10.10` (53, 88, 123, 135, 137-139, 389, 445, 464,
     636, 3268-3269); allow LAN → `10.10.10.20` (80, 443, 587, 465, 993); allow LAN →
     `10.10.10.30` (443); block `10.10.10.30` → `10.10.10.10:389` (forces LDAPS); allow LAN → WAN
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

1. Create a new VM per [`hypervisor/vms/linux-client.md`](../hypervisor/vms/linux-client.md):
   2 vCPU, 4 GB RAM, 40 GB disk, single NIC on `LAN-LAB`, Ubuntu Desktop 24.04 ISO attached.
2. Install Ubuntu Desktop interactively — it gets a DHCP lease from pfSense once step 1 above
   is done.
3. Apply [`hypervisor/desktop/baseline.md`](../hypervisor/desktop/baseline.md).
4. Clone this repository onto it and install the tooling the rest of the guide needs:

   ```bash
   sudo apt update && sudo apt install -y ansible openssl git rsync samba-common-bin whois \
       python3 python3-pip openssh-client
   git clone <this-repo-url> ~/lab-small-business
   cd ~/lab-small-business
   ansible --version   # confirm ansible-core 2.16+
   ```

From here on, "control host" in this guide means **this VM** — every `ansible-playbook`,
`openssl`, and `samba-tool` command from step 3 onward runs from here, not from your hypervisor
host machine. (If you'd rather drive the build from WSL2 on a Windows host instead, see
[docs/WSLSetup.md](WSLSetup.md) — the LAN Segment reachability fix it documents is the only
extra step that path needs.)

## 3. Samba AD Domain Controller

1. Build and install `samba-dc01` by hand, then apply the baseline — see
   [`hypervisor/vms/samba-dc.md`](../hypervisor/vms/samba-dc.md) for the VM spec, static IP, and
   `labadmin`/SSH-key setup.
2. `sudo samba/scripts/bootstrap-ad.sh` — provisions the domain (see
   [SambaAdmin.md](SambaAdmin.md)).
3. `sudo samba/scripts/create-ous.sh && sudo samba/scripts/create-groups.sh && sudo samba/scripts/create-users.sh`
4. `samba/scripts/health-check.sh` — confirm green before proceeding.

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

1. Build and install `docker01` and `authentik01` by hand, then apply the baseline to each —
   see [`hypervisor/vms/docker-server.md`](../hypervisor/vms/docker-server.md) and
   [`hypervisor/vms/authentik.md`](../hypervisor/vms/authentik.md) for VM specs, static IPs, and
   `labadmin`/SSH-key setup.
2. From your control host, populate `ansible/inventory/hosts.ini` (already templated with these
   IPs), `cd ansible`, and run each of the following in order. Each is idempotent and
   individually re-runnable — this is the same sequence `ansible-playbook playbooks/site.yml`
   chains automatically for redeploys (see "One-shot re-runs" below), broken out here so each
   stage is visible on its own:

   ```bash
   ansible-playbook playbooks/00-common-hardening.yml --ask-vault-pass
   ```

   SSH hardening, `ufw`, `unattended-upgrades`, and NTP against `samba-dc01`, applied to all
   three servers (`samba-dc01`, `docker01`, `authentik01`) — plus Fail2Ban on `docker01`/
   `authentik01`. This is `samba-dc01`'s first contact with Ansible: everything in step 3 ran
   directly on the DC over SSH, not through a playbook.

   ```bash
   ansible-playbook playbooks/04-linux-client-join.yml --ask-vault-pass
   ```

   SSSD-joins `docker01` and `authentik01` to `LAB.INTERNAL` — the same underlying mechanism
   `linux-client01` used interactively in step 7's `join-linux-client.sh`, automated here
   because there are two hosts to join instead of one interactive session.

   ```bash
   ansible-playbook playbooks/05-pki-trust.yml --ask-vault-pass
   ```

   Distributes the CA chain built in step 4 to all three servers, `samba-dc01` included (its
   first CA-trust pass too).

   ```bash
   ansible-playbook playbooks/02-docker-server.yml --ask-vault-pass
   ```

   Installs Docker Engine and brings up all 5 Compose stacks (`docker/{reverse-proxy,nextcloud,
   onlyoffice,mail,wordpress,stirling-pdf}`) on `docker01` in one run.

   ```bash
   ansible-playbook playbooks/03-authentik.yml --ask-vault-pass
   ```

   Brings up Authentik and applies its OIDC/LDAP blueprints via
   [`bootstrap-authentik.sh`](../authentik/scripts/bootstrap-authentik.sh) — the actual
   bootstrap logic; Ansible's role here is just plumbing (copy the repo, render `.env`, invoke
   the script).

   ```bash
   ansible-playbook playbooks/99-backups.yml --ask-vault-pass
   ```

   Installs the daily backup timers for Samba AD (`samba-dc01`) and Docker volumes + PKI
   (`docker01`) — see [Backup.md](Backup.md).

3. Verify: `https://auth.lab.internal` loads with a trusted cert and you can sign in as
   `akadmin` (bootstrap credentials in `ansible/inventory/host_vars/authentik01/vault.yml`).

## 6. Applications

NextCloud, OnlyOffice, Dovecot+Postfix, WordPress, and Stirling PDF all came up already, as part
of step 5's `02-docker-server.yml` run — this step is about understanding what you now have, not
deploying anything new. (To reapply this layer later, after editing a Compose file or `.env`,
re-run `ansible-playbook playbooks/02-docker-server.yml --ask-vault-pass` — it's idempotent, so
re-running the whole playbook to pick up one app's change is safe and cheap.)

- **NextCloud** (`https://cloud.lab.internal`) — file storage/groupware. Its "Log in with
  Authentik" button is OIDC against the identity provider you stood up in step 5: NextCloud
  never sees your AD password, only a token from Authentik. Confirm the button is present and
  working.
- **OnlyOffice** (`https://docs.lab.internal`) — the document-editing backend NextCloud calls
  out to for in-browser editing. It's a separate Compose stack/container, not bundled into
  NextCloud, so it can be updated or replaced independently. Confirm the Document Server status
  page loads.
- **Mail** (`mail.lab.internal:993` IMAPS / `:587` submission) — Dovecot and Postfix authenticate
  directly against Samba AD via LDAP bind, not OIDC — a different, older pattern worth
  contrasting with NextCloud's SSO button above. See
  [docker/mail/README.md](../docker/mail/README.md) for a full send/receive test.
- **WordPress** (`https://www.lab.internal`) — installed and ready; unlike the other apps, SSO
  here is opt-in rather than default (see step 6a) — a public-facing CMS doesn't always want
  every visitor routed through the internal identity provider.
- **Stirling PDF** (`https://pdf.lab.internal`) — a third distinct access-control pattern:
  forward-auth. Traefik asks Authentik "is this request allowed?" *before* proxying the request
  at all, rather than the app itself handling an OIDC login like NextCloud does. See
  [docker/stirling-pdf/README.md](../docker/stirling-pdf/README.md).

### 6a. Groupware apps and optional WordPress SSO

```bash
docker/nextcloud/scripts/bootstrap-nextcloud-apps.sh   # Calendar, Contacts, Talk, Mail, ONLYOFFICE connector
docker/wordpress/scripts/configure-oidc-plugin.sh       # optional: wires WordPress into Authentik SSO
```

Both are idempotent and safe to re-run. `scripts/deploy-all.sh` runs the first automatically;
the WordPress one is left manual since SSO-for-a-website is an opt-in decision, not a default.

## 7. Endpoints

`linux-client01` already exists (built manually in step 2). Build and install `win-client01` by
hand, then apply the baseline — see
[`hypervisor/vms/windows-client.md`](../hypervisor/vms/windows-client.md) for the VM spec (note
its UEFI/Secure Boot/vTPM requirement) and install steps. What's left for both clients is
joining the domain:

1. `linux-client01`: `sudo samba/scripts/join-linux-client.sh` (joins domain, configures SSSD,
   installs the CA chain via `ansible-playbook playbooks/05-pki-trust.yml --limit
linux-client01` or manually per [PKI.md](PKI.md)).
2. `win-client01`: confirm DNS is `10.10.10.10` (DHCP-served), then run
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

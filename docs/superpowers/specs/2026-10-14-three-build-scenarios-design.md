# Three Build Scenarios — Design

## Context

Nested virtualisation now works on the lab PCs (`scripts/Set-NestedVirtualisation.ps1`
prepares the Windows host; VMware Workstation then exposes VT-x/EPT to a guest). That makes
Proxmox VE installable *inside* VMware Workstation, which unlocks far more automation than the
VMware-only path allows: Terraform, LXC containers, templates, snapshots, and an API.

The repo today has one primary path (hand-run VMware Workstation, `hypervisor/vmware-*`) and an
add-on Proxmox path (`hypervisor/proxmox`, three Terraform VMs). This design reorganises the repo
around three explicit **build scenarios** that share one core of Ansible, Docker, PKI, Samba and
Authentik content.

## The scenarios

| # | Scenario | Optimised for | Base OS | Apps/services | Automation |
|---|----------|---------------|---------|---------------|------------|
| 1 | **Native VMware VMs** | Learning | Hand-built in the Workstation GUI | Scripted, one step at a time | Low, by design. Step-by-step commands, heavy docs |
| 2 | **Nested Proxmox** (Proxmox VE inside VMware Workstation) | Repeatability in a classroom | Terraform-created | Ansible-driven | High. Mostly LXC, a few VMs |
| 3 | **Native Proxmox** (bare-metal hardware) | A "real" lab | Same as 2 | Same as 2 | Same as 2 |

Scenarios 2 and 3 are **one automation tree**. They differ only in host preparation:

| Step | Scenario 2 (nested) | Scenario 3 (bare metal) |
|------|---------------------|--------------------------|
| Prepare Windows host | `Set-NestedVirtualisation.ps1` | n/a |
| Create the Proxmox "host" | VMware VM with "Virtualize Intel VT-x/EPT" ticked, 8+ vCPU, 32+ GB RAM, disk on SSD | Install on hardware |
| Proxmox install, `post-install.sh` | identical | identical |
| Networking | `vmbr-wan` is the VMware NAT NIC, `vmbr-lan` internal | `vmbr-wan` = spare physical NIC |
| Everything after | identical | identical |

### VMware host OS: Windows and Linux

Scenarios 1 and 2 both run on VMware Workstation Pro on **either a Windows or a Linux host**.

| | Windows host | Linux host |
|---|---|---|
| Scenario 1 VM creation | `hypervisor/vmware-windows/scripts/create-vms.ps1` | `hypervisor/vmware-linux/scripts/create-vms.sh` |
| Scenario 2 nested prep | `scripts/Set-NestedVirtualisation.ps1` (Check / Disable / Restore) | `scripts/check-nested-virtualisation.sh` (read-only check) |
| What blocks nesting | Hyper-V, VBS, Memory Integrity, Credential Guard | `kvm_intel`/`kvm_amd` `nested` parameter off, no `vmx`/`svm` flag, firmware VT-x off |
| Scenario 2 Admin PC | Ubuntu desktop or Windows 11 | same |

Both host OSes share the VM specs, the `LAN-LAB` segment and every Proxmox step after the
VMware VM exists. Guests are mixed Linux and Windows in every scenario (see the course
alignment below). The Linux-host script only checks: nothing on Linux needs switching off the
way Windows features do, so the useful tool is one that explains *why* nesting is unavailable.

Constraint carried over from `CLAUDE.md`: scenario 1 must keep working with the Proxmox trees
deleted, and nothing in the shared core may depend on Proxmox.

## Scenario 2 topology (matches the course spine lab)

The Advanced Server Security plan fixes the nested design as **three VMware VMs**, with all lab
guests inside Proxmox. Scenario 2 adopts it exactly:

```
Internet - VMware NAT - pfSense (VMware VM) - LAN Segment (LAN-LAB) - Admin PC (VMware VM)
                                                      |
                                                Proxmox VE (VMware VM, nested KVM + LXC)
                                                      |  vmbr-lan bridged to the LAN Segment
                                         LXCs + VMs: docker01, authentik01, samba-dc01, Windows Server...
```

Why pfSense stays outside Proxmox here: it avoids a second level of nesting for the firewall,
reuses the repo's existing `LAN-LAB` LAN Segment design unchanged, and frees RAM (32 GB host:
about 4 GB Windows, 1 GB pfSense, 3-4 GB Admin PC, 20 GB for Proxmox and its guests). In
scenario 3 there is no VMware, so pfSense becomes a Proxmox VM on `vmbr-wan` / `vmbr-lan`.
Terraform therefore never manages pfSense in scenario 2.

## Workload placement on Proxmox (scenarios 2 and 3)

| Host | Type | Reason |
|------|------|--------|
| `pfsense01` | VM (scenario 3 only) | FreeBSD, no LXC option. Native VMware VM in scenario 2 |
| Squid proxy | On pfSense, outside Proxmox | It must sit on the path all traffic crosses. See `pfsense/squid.md` |
| `win-client01`, Windows Server | VM | Windows |
| `linux-client01` | VM | Needs a desktop |
| `docker01` | **VM** | Decision: no privileged LXC. See below |
| `authentik01` | **VM** | Runs Docker, same reasoning |
| `samba-dc01` | **VM** | A DC needs reliable ACLs and xattrs. See below |
| Small single-purpose services (monitoring extras, SFTP, test targets) | Unprivileged LXC | Cheap on RAM, no Docker, no special privileges |

### Docker in LXC: is privileged required?

No. Docker runs in an **unprivileged** LXC with `nesting=1,keyctl=1`, and that is the
configuration Proxmox documents. It is still the weaker choice: it weakens the container
boundary (nesting exposes more of the host to the container), and Docker inside an LXC inside a
nested VM has known sharp edges (overlayfs on some storage backends, AppArmor profiles, kernel
upgrades breaking a working setup). A **privileged** LXC is worse still: root in the container is
root on the host. Decision: Docker hosts are **VMs**. This costs RAM (a VM carries its own
kernel) and makes the Terraform-created VMs from the existing module the default, which is
already built. LXC is kept for services that need no Docker and no privileges.

### Provisioning method: Terraform or a script on the Proxmox host?

| | Terraform (`bpg/proxmox`) | Script on the host (`qm`, `pct`, `pvesh`) |
|---|---|---|
| Setup | API token with a role, a trusted certificate on the web UI (this repo refuses `insecure`), Terraform installed, provider downloaded | None. Copy a file, run it as root |
| What students read | HCL plus provider semantics | Plain shell calling the same commands they type by hand |
| Idempotent re-run | Built in: plans a diff from state | You write the checks (`qm status` before `qm create`) |
| State | A state file to protect and not lose | None: Proxmox is the state |
| Teaches | Declarative IaC, plan/apply, drift | How Proxmox actually works; the commands behind the GUI |
| Failure mode | Provider limits (the single-CD-ROM limit already forced a workaround) | A bug in your script |
| Transferable skill | High (industry IaC) | Medium (Proxmox admin) |

Recommendation: **default to host scripts, keep Terraform as an optional extension.** The
course says hand-build first, then rebuild by code, and "automation as the default, hand
building as the skill-builder". A script that wraps the exact commands students typed by hand
is the shortest honest step from week 2 to week 8, with none of the token and certificate
prerequisites in front of the first lesson. Terraform then becomes a worthwhile contrast
("here is the same lab, declared"). The existing `hypervisor/proxmox/` module stays and keeps
working. This is a recommendation; the final choice is yours.

### Risks to resolve in the spike, not assume away

- **Samba AD in an LXC (now a VM by default).** A DC needs POSIX ACLs and `security.*`/`trusted.*` xattrs on its
  sysvol and `idmap` DB. Unprivileged LXCs map UIDs, so `sysvol` ACL handling and `samba-tool
  ntacl sysvolreset` need testing. If it fails, `samba-dc01` stays a VM (the Terraform VM
  module already exists). Make LXC-vs-VM a per-host toggle, not a hard-coded choice.
- **Static IPs and the pfSense dependency.** LXCs boot before pfSense is configured. IPs are
  static on `vmbr-lan`, so this is fine, but the order in the runbook must be pfSense first
  for anything that needs internet.
- **Nested performance.** Three-level nesting is slow for Windows guests. Budget RAM accordingly
  and treat `win-client01` as optional in scenario 2.

## Target repository layout

```
scenarios/
├── README.md                      # picker: which scenario, why, what each needs
├── 1-vmware-manual/               # learning path: ordered steps, commands, explanations
├── 2-nested-proxmox/              # host prep + nested-specific notes, then hands off to proxmox/
└── 3-native-proxmox/              # bare-metal notes, then hands off to proxmox/
hypervisor/
├── proxmox/
│   ├── host/post-install.sh       # repo + nag cleanup (this change)
│   ├── (Terraform: VMs and LXCs)
│   └── README.md
├── vmware-windows/, vmware-linux/ # unchanged; used by scenario 1
└── vms/, networks/                # shared specs
```

`scenarios/` holds the *story* (what to do in what order, and why). `hypervisor/` and the shared
core hold the *mechanism*. The existing `docs/DeploymentGuide.md` becomes the scenario 1
walkthrough's reference rather than being rewritten.

## Proxmox host preparation (this change)

`hypervisor/proxmox/host/post-install.sh` reimplements the community-scripts `post-pve-install`
helper locally rather than piping it into a root shell:

- Disables `pve-enterprise` and `ceph` enterprise repos (they 401 without a subscription).
- Adds `pve-no-subscription`. Handles PVE 8 (`.list`) and PVE 9 (deb822 `.sources`).
- Hides the login subscription popup, re-applied by an apt hook after upgrades.
- `--dry-run` and `--upgrade` options. Idempotent.

Rationale for owning the script: this is a teaching repo, a reviewer can read 150 lines, and
running a third-party script as root from the internet is exactly the habit the Security docs
tell students not to form. It is lab-only: the no-subscription repo gets less testing than
Enterprise.

Not carried over from the community script: disabling HA services and corosync (add later if
RAM is tight), and the upgrade-by-default behaviour.

## Course alignment: Advanced Server Security (ICTNWK540 + ICTNWK546)

Source: `canvas-content-manager/clusters/advanced-server-security-k16` (modernisation plan
draft v3, 13 Oct 2026; ICT50220 Diploma of IT, Advanced Networking). The lab is the **spine
lab** for a 20-week unit: 16 teaching weeks, one module each, all grown on one small-business
platform, feeding AT2 (a continuing design-build-secure-monitor-prove project).

Course rules that shape the lab:

- **Hand-build first, then rebuild from code.** Week 2 hand-installs Linux and Windows; weeks
  4-9 add cloud-init templates and an Ansible role per service week; week 8 prototypes the
  design by code on a throwaway clone. Scenario 1's hand-build steps are therefore also the
  first pass inside scenario 2, and each role must run against a hand-built host and give the
  same result.
- **Definition of done = monitored.** Every service ends with a monitor step (exporter or check,
  one alert rule, one deliberate failure).
- **Linux and Windows are peers (about 60/40).** Windows Server is the commercial reference.
- **32 GB workstation.** LXC for Linux services, one Windows Server guest at a time.
- Nothing may depend on a shared server.

Lab capability against the weekly schedule:

| Wk | Course need | Lab capability today | Status |
|----|-------------|----------------------|--------|
| 1 | Host prep, Proxmox install, bridges, templates, snapshots, Git/SSH | `Set-NestedVirtualisation.ps1`, `post-install.sh`, Proxmox README | Have (spike to prove) |
| 2 | Hand-install Linux + Windows; cloud-init template; rescue environment | `hypervisor/vms/*.md`, seed files | Partial: no template step, no rescue exercise |
| 3 | Requirements and design | `docs/Architecture.md`, diagrams | Have |
| 4 | NTP, DNS, DHCP; **monitoring stack** | Samba DNS/NTP, pfSense DHCP/Unbound | Prometheus, Grafana, blackbox, node_exporter: **done** (`docker/monitoring`, `docs/Monitoring.md`). Still open: Pulse (Proxmox-side), DNS/DHCP failure exercise |
| 5 | Web, reverse proxy + TLS, **filtering proxy**, **SFTP**, host firewall | Traefik, PKI, WordPress | SFTP **done** (`roles/sftp`, `docs/SFTP.md`); Squid **done as pfSense instructions** (`pfsense/squid.md`); host firewalls **done as docs + per-role ufw rules** (`docs/HostFirewalls.md`) |
| 6 | Mail, SPF/DKIM/DMARC, headers | `docker/mail`, `docs/SPFDKIMDMARC.md` | Have |
| 7 | AD, shares, ACLs, GPO, PowerShell provisioning | Samba AD, win-client01 | **Gap:** Windows Server member server or second DC, PowerShell bulk users, file-server role |
| 8 | Prototype by code, test plan | Ansible roles, Terraform | Partial: roles cover the base only; no test-plan template |
| 9 | Backup, restore, RPO/RTO | `docs/Backup.md` | **Gap:** Proxmox Backup Server, timed restore, immutable copy |
| 12-14 | Threat model, risk, security design | Course templates applied to this lab | Content, not lab; lab supplies diagrams and an asset list |
| 15 | CIS/Essential Eight hardening via Ansible and GPO; MFA; PKI; patching | `common`/`fail2ban` roles, Authentik MFA, PKI | **Gap:** CIS roles, GPO, patch service, LAPS |
| 16 | Central logging, alerts, baselines, Wazuh | Fail2ban only | **Gap:** Wazuh or Loki/syslog, benchmark baseline |
| 17 | Vulnerability scan, audit, remediate | none | **Gap:** scanner (for example Greenbone/OpenVAS) and a scan target |
| 18 | IR runbook, timed recovery drill, handover | none in the lab | **Gap:** drill scenario using the monitoring stack |

The gaps are the work list for delivery step 3 onward. Squid, SFTP, monitoring and hardening
belong in the shared core (not under `scenarios/`) because scenario 1 learners need them too.

Points to settle with the course owner:

- The cluster plan describes three VMware VMs; this repo's VMware path builds six. Scenario 2
  follows the cluster; scenario 1 keeps the six-VM hand-build.
- `Set-NestedVirtualisation.ps1` is byte-identical in both repos. Make this repo canonical (it
  also hosts the Linux counterpart) and have the cluster link to it or copy it at build time.
- Pulse and Proxmox Backup Server are named in the course plan; neither is in the repo yet.
- The course spike (`plan/lab-spike.md`, due 21 Oct 2026) proves pfSense + Proxmox + Admin PC.
  Add this repo's LXC risks (Docker-in-LXC, Samba-in-LXC) to its Proxmox section.

## Delivery plan

1. **This change.** This spec, `post-install.sh`, `scenarios/` picker with three skeleton
   READMEs.
2. **Spike on a real lab PC.** Prove nested Proxmox boots; prove Docker-in-LXC and Samba-in-LXC
   (the risks above). Output: decision per host, LXC or VM.
3. **Proxmox automation.** Terraform LXC resources, Ansible inventory for LXC hosts (`pct`/SSH),
   a Proxmox bridge/network bootstrap script, LXC template download step.
4. **Scenario 1 rewrite.** Turn the existing VMware path into a numbered, annotated walkthrough
   with a commented script per step.
5. **Docs sweep.** README index, `Architecture.md`, `DeploymentGuide.md`, `hypervisor/README.md`,
   cross-links, and Makefile targets per scenario.

## Open questions

- Windows Server guests under nested KVM are slow (the course plan says so). Confirm one
  Windows Server guest at a time is the supported design, and whether `win-client01` is optional.
- One Proxmox VM per student, or one shared nested host per bench?
- Where to keep the Proxmox VM sizing: a table here, or the `scenarios/2-nested-proxmox` README.

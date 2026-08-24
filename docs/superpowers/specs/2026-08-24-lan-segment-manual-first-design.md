# LAN Segment networking + manual-first build sequence

## Context

Testing the VM-infra automation from
[2026-08-16-cross-platform-vm-helpers-design.md](2026-08-16-cross-platform-vm-helpers-design.md)
in a real VMware Workstation lab surfaced three problems:

1. **`vnetlib`/`vnetlib64` is broken.** Broadcom has confirmed this in recent VMware Workstation
   updates. `workstation/scripts/configure-vmnet.ps1` wraps it to create the host-only
   `VMnet2` LAN network — that script no longer reliably works.
2. **The pfSense automation (`config.xml.template` import + `pfsense-post-install.sh`) is more
   friction than help this early.** Students should learn pfSense by configuring it manually
   first; the guided/templated config path is worth having but shouldn't be the default
   on-ramp.
3. **Host-only VMnet plumbing is itself the wrong tool for a teaching lab.** It requires the
   Virtual Network Editor, a numbered `VMnetN`, and disabling VMware's own DHCP service on it —
   several steps that don't teach anything about the lab itself and are a common source of
   first-run breakage. VMware Workstation's **LAN Segments** feature (a named, per-VM switch
   created from *VM Settings → Network Adapter → LAN Segments*) needs none of this: no Virtual
   Network Editor, no vnetlib, no built-in DHCP service to disable.

This also creates an opportunity to fix a second known pain point: `docs/WSLSetup.md` exists
solely so WSL2 (running on the Windows host) can reach the host-only `VMnet2` network to act as
the Ansible/PKI control node — a networking fix the doc itself says "trips up almost everyone on
first try." If the control node instead lives *inside* the lab network (on the same LAN Segment
as everything else), that whole cross-boundary reachability problem disappears.

## Decisions

Confirmed with the user (see prior conversation for the reasoning):

- **Only pfSense is dual-homed.** NIC1 → NAT (`VMnet8`, VMware's built-in default, untouched —
  no vnetlib involved). NIC2 → LAN Segment (named `LAN-LAB`). Every other lab VM has a single
  NIC on `LAN-LAB` and reaches the internet only through pfSense's NAT/firewall — the isolation
  model in `docs/Security.md` is unchanged, only the LAN's underlying mechanism changes.
- **`linux-client01` becomes the control node, replacing WSL2.** It moves from
  `DeploymentGuide.md` step 7 (Endpoints, last) to immediately after pfSense. Built manually,
  single NIC on `LAN-LAB`, repo cloned onto it. From that point on, it's the documented host for
  Ansible, the PKI scripts, and `samba-tool` invocations. It still gets domain-joined later, at
  the point in the guide where AD exists — it ends up doing double duty as build driver and
  eventual lab endpoint. `docs/WSLSetup.md` is demoted to an optional appendix for anyone who'd
  rather drive the build from the Windows host instead.
- **`create-vms.ps1` keeps automating the four seed-driven unattended installs**
  (`samba-dc01`, `docker01`, `authentik01`, `win-client01`). `pfsense01` and `linux-client01`
  both drop out of its table — both are fully manual, GUI-built VMs now. Its LAN NIC default
  changes from `VMnet2` to the LAN Segment name `LAN-LAB`; the WAN-NIC plumbing is removed
  entirely since no VM left in its table is dual-homed.
- **pfSense's guide section becomes manual/prose**, not templated: build the VM by hand, install
  pfSense, configure WAN/LAN/DHCP/firewall through the GUI with concrete values spelled out.
  `pfsense/config/config.xml.template` and `pfsense/scripts/pfsense-post-install.sh` stay in the
  repo, relabeled in `pfsense/README.md` as an optional shortcut to revisit later.

## Architecture

```
Internet
   │
   │ (VMware NAT, VMnet8 — built-in, unmanaged by this repo)
   │
pfSense (NIC1: NAT, NIC2: LAN Segment "LAN-LAB")
   │  10.10.0.1/24 — gateway, firewall, DHCP, DNS forwarder
   │
   └── LAN Segment "LAN-LAB" (10.10.0.0/24, no VMware-side DHCP — pfSense is the only DHCP server)
        │
        ├── linux-client01   — Ubuntu Desktop, control node (manual build, first after pfSense)
        ├── samba-dc01       — AD DC (create-vms.ps1, seed-driven)
        ├── docker01         — Docker Engine + Traefik (create-vms.ps1, seed-driven)
        ├── authentik01      — Authentik IAM (create-vms.ps1, seed-driven)
        └── win-client01     — Windows 11 (create-vms.ps1, seed-driven)
```

Every VM below pfSense has exactly one NIC, on `LAN-LAB`. No VM other than pfSense ever has a
NAT/WAN-facing NIC — that invariant is what makes the firewall rules in `docs/Security.md`
meaningful, and it doesn't change from the current design.

## Build sequence (replaces `DeploymentGuide.md` steps 0-2 and 7)

1. **Host prerequisites** — VMware Workstation Pro, ISOs downloaded. No PowerShell
   networking step here anymore (no `configure-vmnet.ps1` to run) — the LAN Segment is created
   as part of building pfSense's second NIC, not as a prior standalone step.
2. **pfSense — fully manual.** New VM in the Workstation GUI: NIC1 defaults to NAT
   (`VMnet8`), NIC2 added as a LAN Segment named `LAN-LAB` (created inline via the "LAN
   Segments..." picker — this is the one and only place that name gets created). Install
   pfSense interactively. Configure WAN/LAN/DHCP/firewall by hand, with concrete values spelled
   out in the guide (LAN `10.10.0.1/24`, DHCP pool `10.10.0.100-199`, DNS forwarder →
   `10.10.0.10` once the DC exists, NAT/firewall rules). `config.xml.template` +
   `pfsense-post-install.sh` are mentioned as an optional shortcut, not the default path.
3. **linux-client01 — control node, fully manual.** New VM in the Workstation GUI: single
   NIC on `LAN-LAB`. Install Ubuntu Desktop 24.04 interactively, gets a DHCP lease from pfSense.
   Clone this repo onto it. `apt install ansible openssl rsync samba-common-bin` (same package
   list `WSLSetup.md` documents today, just run inside this VM instead of WSL2). From here on,
   this VM is "the control host" referenced by the rest of the guide.
4. **samba-dc01 → PKI → docker01/authentik01 → applications** — unchanged in substance from
   today's steps 3-6, except every command that today says "run this from WSL2" now says "run
   this from `linux-client01`."
5. **Endpoints (step 7)** — shrinks to just `win-client01` (install, join domain,
   `join-windows-client.ps1`) plus `linux-client01`'s domain-join
   (`join-linux-client.sh`), now that its VM already exists and has the repo on it.

## Component changes

| File | Change |
| --- | --- |
| `workstation/scripts/configure-vmnet.ps1` | Delete. No vnetlib call is needed — LAN Segments are created inline from a VM's Network Adapter settings. |
| `workstation/networks/README.md` | Rewrite: describe the LAN Segment (`LAN-LAB`) instead of host-only `VMnet2`; drop the Virtual Network Editor / vnetlib / "disable built-in DHCP" content (LAN Segments have no built-in DHCP service to disable). |
| `workstation/scripts/create-vms.ps1` | Remove `pfsense01` and `linux-client01` from the `$VMs` table. Rename `-LanNetwork` default from `"VMnet2"` to `"LAN-LAB"`. Remove `-WanNetwork` param and all WAN-NIC logic (no remaining table entry is dual-homed). |
| `workstation/README.md` | Update the script inventory description — `configure-vmnet.ps1` bullet removed, `create-vms.ps1` bullet notes it covers 4 VMs, not 6. |
| `workstation/vms/pfsense.md` | Rewrite as a full manual build walkthrough: New VM wizard settings, NIC1 (NAT, default), NIC2 (LAN Segment `LAN-LAB`, created here), pfSense install, WAN/LAN/DHCP/firewall GUI configuration with concrete values. Note `config.xml.template` as an optional shortcut. |
| `workstation/vms/linux-client.md` | Rewrite: moves earlier in the sequence, single NIC on `LAN-LAB`, becomes the control node; keep its existing domain-join content but note it now runs later than VM creation. |
| `diagrams/network-topology.md` | Relabel the LAN subgraph from "LAN — VMnet-LAB (Host-only)" to "LAN — LAN Segment `LAN-LAB`"; no topology change otherwise. |
| `docs/DeploymentGuide.md` | Restructure steps 0-2 and 7 per the build sequence above. |
| `docs/WSLSetup.md` | Demote to a short optional appendix: "prefer to drive this from the Windows host instead of `linux-client01`? Here's the WSL2-to-LAN-Segment networking fix." Trim the "why WSL2 not Git Bash" framing since it's no longer the default path. |
| `docs/Architecture.md` | Update network-design and control-host mentions to match. |
| `pfsense/README.md` | Add a note that `config.xml.template` + `pfsense-post-install.sh` are an optional shortcut for once the manual path is familiar, not the first-run default. |

No changes needed to `ansible/inventory/`, `Makefile`, or `scripts/deploy-all.sh` — checked, and
none of them encode WSL2- or vnetlib-specific assumptions; they're agnostic to which POSIX host
runs them.

## Risks / open assumptions

- **LAN Segment `.vmx` mechanics are assumed, not verified against a live Workstation
  install.** `create-vms.ps1` already writes `ethernetN.connectionType = "custom"` /
  `ethernetN.vnet = "<name>"` for its NICs — this is believed to be the same mechanism LAN
  Segments use internally (a named switch rather than a numbered `vmnetN` device), so pointing
  that same field at `"LAN-LAB"` should work unchanged. This needs to be confirmed on the first
  real run. If a scripted `.vmx` reference doesn't auto-register a new LAN Segment the way the
  GUI's "LAN Segments..." picker does, the fallback is: create `LAN-LAB` once via the GUI
  (naturally happens anyway, in step 2 above, when pfSense's NIC2 is added), after which
  `create-vms.ps1`'s VMs can reference it by name with no further manual step.
- **Two repo clones.** The repo ends up cloned both on the Windows host (to run
  `create-vms.ps1`, which needs `vmrun.exe`/PowerShell) and on `linux-client01` (to run
  everything from step 4 onward). This is a deliberate consequence of the control node moving
  inside the lab network, not an oversight — worth calling out explicitly in
  `DeploymentGuide.md`'s prerequisites so it doesn't read as accidental duplication.

## Testing

No CI in this repo (per `CLAUDE.md`). Validation is: `bash -n` / PowerShell syntax check on
every script touched, and a careful read of every doc changed for consistency with the new
sequence. The user will validate the LAN Segment `.vmx` assumption and the manual pfSense/
`linux-client01` build steps against a real VMware Workstation lab and report back — this repo
has no way to spin up VMs from this environment.

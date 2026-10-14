# Extract Proxmox into `lab-scale-business` — Design

## Context

This is sub-project **B** of a five-part restructuring effort (D → A → C → B → E). D, A, and C
are implemented. B is different in kind from the other four: it doesn't restructure this repo's
own content, it creates a **new, separate repository** and removes a whole platform from this
one. Per the originating request: Proxmox (and eventually ESXi) is "the place for automation" —
this repo's now-guided, manual VMware/Fusion path (sub-project A) and this new automated repo
are two different products for two different audiences, not two options inside one repo.

Scoped down from the full "environment in a box" vision (fully automated VM-through-app-layer
deployment, plus new ESXi support) to a bounded extraction: move `hypervisor/proxmox/` to a new
repo exactly as it works today (Terraform provisions VM shells for 3 of 6 VMs; everything else —
PKI, Ansible, Docker apps — is still the same manual/guided sequence `docs/DeploymentGuide.md`
documents for every platform). The fuller vision is written down as a roadmap in the new repo,
not built now.

## Goal

1. Create a new local git repository, `lab-scale-business`, at
   `/home/andy/Development/lab-scale-business` (sibling to this repo), containing the Proxmox
   Terraform module, its seed files, a README explaining current scope and relationship to
   `lab-small-business`, and a ROADMAP documenting the full automation vision as future work.
2. Remove every trace of Proxmox from this repo (`lab-small-business`): the `hypervisor/proxmox/`
   directory, the 3 `proxmox-user-data.example` seed files (and the now-empty
   `hypervisor/vms/seeds/` tree they leave behind), every "On Proxmox" aside across the 6
   `hypervisor/vms/*.md` pages, and every Proxmox-alternative-path mention in `hypervisor/README.md`,
   `hypervisor/networks/README.md`, `docs/DeploymentGuide.md`, `docs/Architecture.md`,
   `README.md` (top-level), `pfsense/README.md`, and `CLAUDE.md`.

## Non-goals

- **Not pushed to GitHub.** The new repo is `git init`-ed locally only; publishing it (creating
  a remote, choosing public/private) is left to the user, per their explicit choice.
- **No full end-to-end automation built.** The new repo's Terraform module does exactly what it
  does today — provisions VM shells for `samba-dc01`/`docker01`/`authentik01` via cloud-init.
  Chaining in a fully-automated Ansible app-layer bring-up, and building ESXi support, are
  documented in the new repo's `ROADMAP.md` as future work, not implemented here.
- **No changes to any Terraform resource's behavior.** `main.tf`'s provider config, `variables.tf`'s
  variable definitions, and `vms.tf`'s VM resources move verbatim — the only functional change is
  updating relative paths that assumed the old repo's directory nesting (see Design).
- **No changes to this repo's remaining hypervisor platform (`hypervisor/desktop/`)** beyond
  removing Proxmox's row from `hypervisor/README.md`'s comparison table. Sub-project A already
  covers the desktop path in full.

## Design

### New repo layout (`lab-scale-business`)

```
lab-scale-business/
├── README.md              # what this is, current scope, relationship to lab-small-business
├── ROADMAP.md              # full automation vision, ESXi support — documented, not built
├── .gitignore              # .terraform/, *.tfstate*, *.tfvars (not .example), seeds/*/proxmox-user-data
├── terraform/
│   ├── main.tf              # moved verbatim from hypervisor/proxmox/main.tf
│   ├── variables.tf         # moved from hypervisor/proxmox/variables.tf; 2 comment references updated
│   ├── vms.tf                # moved from hypervisor/proxmox/vms.tf; path + comments updated (below)
│   └── terraform.tfvars.example  # moved verbatim
└── seeds/
    ├── samba-dc01/proxmox-user-data.example    # moved verbatim
    ├── docker01/proxmox-user-data.example       # moved verbatim
    └── authentik01/proxmox-user-data.example    # moved verbatim
```

Terraform moves into its own `terraform/` directory at the new repo's root (not nested under a
`hypervisor/` parent that no longer exists in this project), and seed files move to a top-level
`seeds/` directory as a sibling to `terraform/`, rather than living 3 levels deep under a `vms/`
folder that doesn't exist here. This means `vms.tf`'s seed-file path changes from
`${path.module}/../vms/seeds/${each.key}/proxmox-user-data` (old repo: `hypervisor/proxmox/` →
`hypervisor/vms/seeds/`) to `${path.module}/../seeds/${each.key}/proxmox-user-data` (new repo:
`terraform/` → `seeds/`, both at repo root) — same relative depth (one level up, then down into
`seeds/`), just a shorter path since there's no `vms/` layer to descend through.

Three comments move with their files but get corrected, since they referenced this repo's
now-partly-deleted structure (`hypervisor/vmware-linux/scripts/create-vms.sh` no longer exists
even in `lab-small-business`, after sub-project A) or files that don't exist in the new repo
(`hypervisor/networks/README.md`, `proxmox/README.md`):

- `vms.tf`'s top comment: describes the 3 automated VMs' specs and that `win-client01`/
  `pfsense01`/`linux-client01` are manual, pointing at this repo's own `README.md` instead of
  `hypervisor/README.md`/`hypervisor/vms/windows-client.md`.
- `variables.tf`'s `image_datastore` and `cloud_image_path` comments: point at this repo's own
  `README.md` instead of `proxmox/README.md`.
- `variables.tf`'s `lan_bridge` comment: describes the bridge inline instead of pointing at
  `hypervisor/networks/README.md` (doesn't exist here).

### New repo's `README.md`

Adapted from `hypervisor/proxmox/README.md`'s content (prerequisites, bring-up steps, what's
still manual — all still accurate, just re-pathed for `terraform/`/`seeds/` instead of
`hypervisor/proxmox/`/`../vms/seeds/`), plus a new opening section: what this project is ("Build
a small-business IT environment in a box" — Terraform + Proxmox VE), that it was extracted from
`lab-small-business` (a teaching repo taking a deliberately manual/guided approach to the same
environment — link by name, no live URL since that repo isn't necessarily published either), and
current scope (3 of 6 VMs automated today; see `ROADMAP.md` for the rest).

### New repo's `ROADMAP.md`

Documents, as explicit future work rather than built functionality:

- A fully-automated app layer chained after `terraform apply` — reusing/adapting this repo's
  Ansible roles (`docker_engine`, `common`, `fail2ban`, `pki_trust`, `sssd_client`) plus
  re-introducing Samba AD automation (deliberately removed from `lab-small-business` in
  sub-project C as redundant with its guided manual path — not redundant here, since there's no
  manual path in this repo to duplicate).
- ESXi support as a second automated platform, alongside Proxmox.
- `win-client01` automation, if/when a Terraform-expressible unattended-Windows-install
  mechanism becomes available for either platform (today's blocker — a single-`cdrom`-block
  provider limitation — is documented in the moved `README.md`).

### Cleanup in `lab-small-business`

- Delete `hypervisor/proxmox/` (all 5 files) and
  `hypervisor/vms/seeds/{samba-dc01,docker01,authentik01}/proxmox-user-data.example`. The
  `hypervisor/vms/seeds/` tree (already emptied of its VMware-side files in sub-project A) is now
  fully empty — delete it entirely, including the empty `win-client01/` subdirectory sub-project A
  left behind.
- Remove `.gitignore`'s now-dead `hypervisor/vms/seeds/**/proxmox-user-data` line.
- Remove the "**On Proxmox**"/"### On Proxmox" aside from each of `hypervisor/vms/{pfsense,
  linux-client,samba-dc,docker-server,authentik,windows-client}.md` — 6 files, each loses one
  self-contained paragraph (or, for `pfsense.md`, one subsection) with no other content nearby
  needing to change.
- `hypervisor/README.md`: a table titled "Choosing a platform" no longer makes sense with one
  row, so this section is converted to prose describing the `desktop/` path directly (still
  covering the same information the single surviving row + its explanatory paragraphs did — VM
  creation via hypervisor GUI, `desktop/` as the directory, guided baseline) instead of a
  comparison table. The "different kind of platform" paragraph (which contrasted VMware against
  Proxmox) is removed — there's nothing left to contrast against. The "Why hand-built, not
  scripted?" section's closing sentence, which currently says "If you want the 'spin up a whole
  environment in a box' automated experience instead, that's what the Proxmox path is for," is
  replaced with a pointer to `lab-scale-business` by name (no live link, not yet published).
- `hypervisor/networks/README.md`: remove the "## Proxmox equivalent" section (its only content
  is now-broken links to `../proxmox/vms.tf` and `../proxmox/README.md`).
- `docs/DeploymentGuide.md`: intro paragraph loses its "unless you're on Proxmox VE instead —
  see hypervisor/README.md... hypervisor/proxmox/README.md..." clause.
- `docs/Architecture.md`: line 9's "on a single VMware Workstation host or a Proxmox VE..."
  becomes VMware/Fusion-only; line 126's repository-layout comment drops "or Proxmox VE".
- `README.md` (top-level): line 43's repository-layout comment drops "or Proxmox VE"; the Quick
  Start block's `cd hypervisor/proxmox && terraform apply` alternative-path line is removed
  entirely (the block already covers the desktop path fully as of sub-project A).
- `pfsense/README.md`: line 11's "that page covers both the VMware and Proxmox build steps" is
  corrected — `pfsense.md` is VMware/Fusion-only after this change.
- `CLAUDE.md`: line 8's "VMware Workstation (Windows or Linux) or Proxmox VE" becomes
  VMware Workstation/Fusion Pro-only, matching `hypervisor/README.md`'s post-A/B state.

## Testing

No test suite. Verification is:

- `terraform validate` (or, if Terraform isn't installed in the verification environment, a
  manual read of the 3 moved `.tf` files confirming valid HCL syntax and that the one changed
  path resolves correctly) from `lab-scale-business/terraform/`.
- Grep sweep of `lab-small-business` for `proxmox`/`Proxmox`/`PVE` after cleanup — expect zero
  hits outside historical `docs/superpowers/` records.
- Grep sweep of `lab-small-business` confirming no remaining reference to
  `hypervisor/vms/seeds/` (the directory no longer exists).
- Manual read-through of every edited file's surrounding context, confirming no dangling
  cross-reference or now-single-row table renders oddly.

## Open questions

None — this sub-project is fully scoped by the design above.

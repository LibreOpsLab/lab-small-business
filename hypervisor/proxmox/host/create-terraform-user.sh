#!/usr/bin/env bash
# Prepare a Proxmox host for Terraform: a least-privilege role, a user, an API token, and the
# storage content types the module needs. Run ON the Proxmox host as root, once, after
# post-install.sh.
#
# Why a script for this? Terraform needs credentials before it can do anything, and creating
# them by clicking through Datacenter > Permissions is slow and easy to get wrong. This does
# the same thing with the pveum commands you would otherwise type, so you can read them.
#
# The token secret is printed ONCE. Copy it into terraform.tfvars (gitignored).
#
# Usage:
#   ./create-terraform-user.sh --dry-run
#   ./create-terraform-user.sh
#
# Not yet run on a real host: confirm the privilege list against the bpg/proxmox provider
# documentation for the version pinned in ../terraform/main.tf.

set -euo pipefail

# Same helpers as scripts/lib/common.sh (inline so the file can be copied to the host alone).
log()  { printf '\033[1;34m[pve-tf]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[pve-tf][warn]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[pve-tf][error]\033[0m %s\n' "$*" >&2; exit 1; }

DRY_RUN=0
[ "${1:-}" = "--dry-run" ] && DRY_RUN=1

ROLE="TerraformLab"
USER_ID="terraform@pve"
TOKEN_ID="lab"
STORAGE="local"
# What the bpg/proxmox provider needs to create VMs, containers and downloaded files.
PRIVS="Datastore.Allocate Datastore.AllocateSpace Datastore.AllocateTemplate Datastore.Audit \
Pool.Allocate Sys.Audit Sys.Console Sys.Modify SDN.Use \
VM.Allocate VM.Audit VM.Clone VM.Config.CDROM VM.Config.Cloudinit VM.Config.CPU VM.Config.Disk \
VM.Config.HWType VM.Config.Memory VM.Config.Network VM.Config.Options VM.Migrate VM.Monitor VM.PowerMgmt"

run() {
  if [ "${DRY_RUN}" -eq 1 ]; then log "[dry-run] $*"; else "$@"; fi
}

[ "$(id -u)" -eq 0 ] || die "Run as root on the Proxmox host."
command -v pveum >/dev/null 2>&1 || die "pveum not found: this does not look like a Proxmox VE host."

# 1. Role. "role add" fails if it exists, so modify instead on a re-run.
if pveum role list --output-format json | grep -q "\"roleid\":\"${ROLE}\""; then
  log "role ${ROLE} exists, updating its privileges"
  run pveum role modify "${ROLE}" -privs "${PRIVS}"
else
  log "creating role ${ROLE}"
  run pveum role add "${ROLE}" -privs "${PRIVS}"
fi

# 2. User, with no password: it can only be used through its API token.
if pveum user list --output-format json | grep -q "\"userid\":\"${USER_ID}\""; then
  log "user ${USER_ID} exists"
else
  log "creating user ${USER_ID}"
  run pveum user add "${USER_ID}" --comment "Terraform for the lab"
fi

# 3. Grant the role on the whole tree. A token with --privsep 0 inherits the user permissions.
log "granting ${ROLE} to ${USER_ID} on /"
run pveum aclmod / -user "${USER_ID}" -role "${ROLE}"

# 4. Token. The secret exists only in this command output.
if pveum user token list "${USER_ID}" --output-format json | grep -q "\"tokenid\":\"${TOKEN_ID}\""; then
  warn "token ${USER_ID}!${TOKEN_ID} already exists. Its secret cannot be shown again."
  warn "To get a new one: pveum user token remove ${USER_ID} ${TOKEN_ID}, then run this again."
else
  log "creating token ${USER_ID}!${TOKEN_ID}. COPY THE VALUE BELOW NOW, it is shown once."
  run pveum user token add "${USER_ID}" "${TOKEN_ID}" --privsep 0
fi

# 5. Storage content types. download_file needs "import" and "vztmpl" on the image datastore.
current="$(pvesh get "/storage/${STORAGE}" --output-format json | python3 -c 'import sys,json; print(json.load(sys.stdin).get("content",""))')"
wanted="${current}"
for t in import vztmpl; do
  case ",${wanted}," in *",${t},"*) ;; *) wanted="${wanted:+${wanted},}${t}" ;; esac
done
if [ "${wanted}" != "${current}" ]; then
  log "enabling content types on ${STORAGE}: ${wanted}"
  run pvesm set "${STORAGE}" --content "${wanted}"
else
  log "storage ${STORAGE} already allows import and vztmpl"
fi

log "Done. In ../terraform/terraform.tfvars set:"
log "  proxmox_api_token = \"${USER_ID}!${TOKEN_ID}=<the secret printed above>\""

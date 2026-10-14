# Proxmox VE (scenarios 2 and 3)

Terraform builds the Linux guests on a Proxmox host. The same module serves both scenarios:
[scenario 2](../../scenarios/2-nested-proxmox/README.md) (Proxmox inside VMware Workstation)
and [scenario 3](../../scenarios/3-native-proxmox/README.md) (Proxmox on hardware). Only the
host preparation differs.

| Created by Terraform | Type | Why |
|---|---|---|
| `samba-dc01`, `docker01`, `authentik01` | VM (cloud image + cloud-init) | No privileged LXC and no Docker in LXC |
| `pbs01` (Proxmox Backup Server) | Unprivileged LXC | Small, needs neither Docker nor privileges |

Built by hand, as on every platform: pfSense (no unattended installer, see
[`../vms/pfsense.md`](../vms/pfsense.md)), the Windows machines and the Linux desktop. Sizes and
what runs when: the [scenario 2 sizing table](../../scenarios/2-nested-proxmox/README.md#reference-lab-pc-and-sizing).

## Why Terraform, and what it costs

Terraform is declarative: you describe the lab and it works out what to change, and it records
what it built in a state file. That makes the lab rebuildable and reviewable, and it is the
industry skill the course wants taught. The price is setup: an API token, a trusted
certificate, and a provider to learn. The scripts in [`host/`](host/) take most of that setup
away without hiding it. Students hand-build first (course week 2), then rebuild from code
(week 8), so the lesson is "the same lab, declared".

## Layout

```text
host/       run ON the Proxmox host as root
  post-install.sh           repositories and the subscription popup
  create-terraform-user.sh  least-privilege role, user, API token, storage content types
terraform/  run from your workstation
  main.tf variables.tf vms.tf lxc.tf outputs.tf terraform.tfvars.example
guests/     run inside a guest after Terraform created it
  pbs-install.sh            install Proxmox Backup Server in pbs01
```

## Bring-up

1. **Host:** install Proxmox VE, then on the host as root:

   ```bash
   ./post-install.sh --upgrade
   ./create-terraform-user.sh --dry-run    # read it, then run it without --dry-run
   ```

   Copy the token secret it prints. It is shown once.
2. **Networks:** create `vmbr-lan` (no physical port, no IP). In scenario 2 this bridge carries
   the same traffic as the VMware `LAN-LAB` segment; see
   [`../networks/README.md`](../networks/README.md). Add an IP for the host itself outside the
   DHCP pool, for example `10.10.10.5/24`, so pfSense and the clients can reach its web UI.
3. **Trust the Proxmox certificate** (next section).
4. **Terraform**, from a machine with Terraform 1.6 or later:

   ```bash
   cd hypervisor/proxmox/terraform
   cp terraform.tfvars.example terraform.tfvars   # fill in the URL, token and your SSH public key
   terraform init
   terraform plan
   terraform apply
   ```

5. **PBS:** from the Proxmox host, `pct exec 150 -- bash -s < guests/pbs-install.sh`, then follow
   the steps it prints to set a password and add it as storage.
6. **Configure the guests** with Ansible from `linux-client01`, as in
   [`docs/DeploymentGuide.md`](../../docs/DeploymentGuide.md). Each guest is reachable as
   `labadmin` with your SSH key.

## Trusting the Proxmox certificate

This module never sets `insecure = true`. Terraform must be able to verify Proxmox's HTTPS
certificate. Two ways:

- **Best:** issue it from the lab's own PKI and install it, so the lab's CA already trusted by
  every machine covers Proxmox too:

  ```bash
  pki/scripts/02-issue-server-cert.sh --cn pve.lab.internal --san DNS:pve.lab.internal
  # copy the fullchain and key to the host, then on the host:
  pvenode cert set fullchain.pem key.pem --force --restart
  ```

- **Quick:** copy `/etc/pve/pve-root-ca.pem` from the host to your workstation and add it to the
  workstation's trust store (Linux: `update-ca-certificates`; Windows: `certutil -addstore Root`).

Either way, point `proxmox_api_url` at a name that matches the certificate.

## Things that surprise people

- **Set the CPU type to `host` on every VM.** Terraform does this for the VMs it builds. For any
  VM you create by hand (pfSense, Windows, a template), choose Hardware > Processor > Type >
  `host`. Proxmox's default is a generic virtual CPU: it can leave a modern guest unable to
  start, as one did in the lab spike, and it hides CPU features the guest could use for speed.
  The trade-off is that a `host` VM cannot live-migrate between different CPU models, which does
  not matter on a single lab node.

- **Terraform state holds secrets.** `terraform.tfstate` is gitignored. Do not commit it or
  paste it into a chat.
- **Re-running is safe.** `terraform plan` shows what would change; a second `apply` with no
  edits changes nothing. `terraform destroy` removes every guest it created, so use it for a
  clean rebuild and never on a lab holding work you want to keep (back up first with PBS).
- **Ubuntu image URL moves.** The `current` cloud image is replaced as Ubuntu patches it, which
  is why there is no pinned checksum. For a reproducible class build, pin a dated image URL.
- **Container template names change** with Debian point releases. Update `lxc_template_url`
  from `pveam available --section system`.

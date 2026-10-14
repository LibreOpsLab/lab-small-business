# Build Scenarios

The same lab (pfSense, Samba AD, PKI, Authentik, the Docker application stacks, and the clients)
can be built three ways. Pick one. The services end up the same; what changes is how much you
build by hand and what the host is.

| # | Scenario | You choose this when | Effort by hand | Automation |
|---|----------|----------------------|----------------|------------|
| 1 | [Native VMware VMs](1-vmware-manual/) | You want to **learn** how each piece is built | High | Low. Scripts run step by step, each explained |
| 2 | [Nested Proxmox](2-nested-proxmox/) | You want a **repeatable** lab on a normal lab PC | Low | High. Terraform + Ansible; Linux VMs, small services in LXC |
| 3 | [Native Proxmox](3-native-proxmox/) | You have **spare hardware** and want it to feel real | Low | Same as 2 |

Scenarios 2 and 3 share one automation tree ([`hypervisor/proxmox/`](../hypervisor/proxmox/README.md)).
They differ only in how the Proxmox host is prepared.

## What every scenario needs

- The shared core: [`ansible/`](../ansible/), [`docker/`](../docker/), [`pki/`](../pki/),
  [`samba/`](../samba/), [`authentik/`](../authentik/).
- The same network design: [`hypervisor/networks/`](../hypervisor/networks/README.md).
- The same VM specs: [`hypervisor/vms/`](../hypervisor/vms/).

## Status

Design: [three-build-scenarios-design.md](../docs/superpowers/specs/2026-10-14-three-build-scenarios-design.md).
Scenario 1 works today (see its README). Scenarios 2 and 3 have host preparation in place; the
LXC automation is the next piece of work.

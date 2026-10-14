# Scenario 1: Native VMware VMs

**Goal: learning.** You install each base OS yourself in VMware Workstation (or Fusion), then run
a script for each service, one at a time, reading what it does as you go. Nested virtualisation
is **not** needed. This is the repo's main path and it is hand-built by design: see
[Why hand-built, not scripted?](../../hypervisor/README.md#why-hand-built-not-scripted).

This is also the "hand-build first" half of the Advanced Server Security unit: week 2
hand-installs Linux and Windows, and later weeks rebuild the same machines from code
(scenario 2).

## Host OS: Windows or Linux

VMware Workstation Pro runs on both; Fusion Pro covers macOS. The guest VMs, networks and steps
are identical. See [`hypervisor/desktop/README.md`](../../hypervisor/desktop/README.md).

| | Windows host | Linux host |
|---|---|---|
| Hypervisor | Workstation Pro | Workstation Pro |
| Admin / control host | WSL 2 ([`docs/WSLSetup.md`](../../docs/WSLSetup.md)) or `linux-client01` | the host itself, or `linux-client01` |

## Steps

1. Host and VMware basics: [`hypervisor/desktop/README.md`](../../hypervisor/desktop/README.md).
2. Networks: [`hypervisor/networks/README.md`](../../hypervisor/networks/README.md).
3. VM specs and build steps: [`hypervisor/vms/`](../../hypervisor/vms/), with the shared
   [baseline](../../hypervisor/desktop/baseline.md).
4. The full ordered walkthrough: [`docs/DeploymentGuide.md`](../../docs/DeploymentGuide.md).

## Planned

- A Windows Server member server, joined to the domain like every other host.
- The course-driven additions (logging, scanning, CIS hardening). See the
  [design](../../docs/superpowers/specs/2026-10-14-three-build-scenarios-design.md).

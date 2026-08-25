# WSL2 as an alternative control host

This lab's default control host is `linux-client01` (see
[docs/DeploymentGuide.md](DeploymentGuide.md#2-admin-desktop--linux-client01-control-host)) — a
VM built inside the lab's own LAN Segment, so it needs no special networking setup to reach the
rest of the lab.

If you'd rather drive the deployment tooling — Ansible, the PKI shell scripts, `samba-tool`
invocations, `rsync` — from the Windows host instead, via WSL2, this doc covers what that path
needs: why WSL2 (not Git Bash), how to configure its networking so it can reach the lab's
`LAN-LAB` LAN Segment, and how to point VS Code at it.

## Why WSL2, not Git Bash

Git Bash (bundled with Git for Windows) is enough for quick edits and running individual
scripts, but it cannot be this repo's **control node**:

- **Ansible does not support Windows as a control node at all** — not "poorly," not "with
  workarounds," genuinely not supported. `ansible-core` requires a POSIX environment
  (Linux, macOS, or WSL) to run `ansible-playbook` from. Since
  [`ansible/playbooks/site.yml`](../ansible/playbooks/site.yml) is how every VM after
  `samba-dc01` gets configured, something has to be able to run it.
- **Git Bash is MinGW, not a Linux kernel.** No `rsync` (which
  [`ansible.posix.synchronize`](https://docs.ansible.com/ansible/latest/collections/ansible/posix/synchronize_module.html)
  — used throughout `ansible/roles/*` to copy this repo onto each managed host — depends on),
  unreliable POSIX permission semantics, no real `systemd`/service concepts, and package
  installation for tools like `samba-common-bin` (needed if you want `samba-tool` available
  from the control host — see
  [`docker/mail/scripts/enable-spam-protection.sh`](../docker/mail/scripts/enable-spam-protection.sh))
  isn't a thing.
- **WSL2 runs an actual Linux kernel** (unlike WSL1's translation layer), so `apt install
ansible openssl rsync samba-common-bin` behaves exactly like it would on any of this lab's
  Ubuntu VMs — no surprises, no missing syscalls.

Keep Git Bash for what it's good at (quick single-script runs, `git` itself); if you're taking
this path instead of `linux-client01`, use WSL2 for everything
[`docs/DeploymentGuide.md`](DeploymentGuide.md) documents from step 3 onward.

## Install WSL2

```powershell
# Elevated PowerShell
wsl --install -d Ubuntu-24.04
```

Ubuntu 24.04 is the same release used throughout this repo's VMs (`samba-dc01`, `docker01`,
`authentik01`) — matching versions means `apt` package availability and behaviour lines up
with what you'll see when you SSH into the actual lab hosts. Reboot if prompted, then complete
the Ubuntu first-run (set a username/password inside the WSL instance — unrelated to any lab
domain account).

Verify you're on WSL2 (not the older WSL1) and check your version:

```powershell
wsl --list --verbose
wsl --version
```

If `wsl --version` reports below `2.0.0`, run `wsl --update` — the mirrored networking mode
below needs a reasonably current version.

## Networking: the part that actually trips people up

This is the one genuinely non-obvious step. By default, WSL2 puts itself behind its **own**
NAT'd virtual switch — separate from VMware Workstation's `LAN-LAB` LAN Segment
(`10.10.10.0/24`) that pfSense and every lab VM live on. Concretely: **out of the box, your WSL2
shell cannot reach `10.10.10.1` (pfSense) at all**, even though the Windows host it's running on
can. Every `ansible-playbook` run and every `ssh samba-dc01.lab.internal` from WSL depends on
fixing this first.

### Fix: mirrored networking mode (recommended, Windows 11 22H2+)

Mirrored mode makes WSL2 share the Windows host's network interfaces directly — including
whichever adapter VMware assigned to the `LAN-LAB` LAN Segment — instead of running behind its
own NAT. This is the simplest correct fix and needs no manual routes or port proxies.

Create or edit `%UserProfile%\.wslconfig` on the **Windows** side (not inside WSL):

```ini
[wsl2]
networkingMode=mirrored
```

Then restart WSL for it to take effect:

```powershell
wsl --shutdown
```

Reopen your WSL terminal and verify:

```bash
ping -c 2 10.10.10.1        # pfSense LAN IP - should respond
ip addr                     # you should see the same adapters Windows itself has, including
                             # the one VMware assigned the LAN-LAB LAN Segment
```

### Fallback: NAT mode + explicit route (older Windows/WSL versions)

If `networkingMode=mirrored` isn't available (Windows 10, or WSL below the version that
supports it), WSL2's default NAT mode needs an explicit route added on the **Windows** side so
traffic to `10.10.10.0/24` gets sent into the WSL2 NAT interface, and pfSense needs to know how
to route the reply back. This is materially more fragile (the WSL2 NAT subnet can change
across reboots) — upgrading Windows/WSL to support mirrored mode is worth doing before falling
back to this. If you're stuck on it:

1. Find WSL2's current gateway IP: `wsl hostname -I` (inside WSL) or check
   `Get-NetIPAddress` on the `vEthernet (WSL)` adapter in Windows.
2. Add a route on the Windows host so `10.10.10.0/24` is reachable via that gateway (exact
   `route add` invocation depends on your WSL2 subnet, which is why mirrored mode is strongly
   preferred — this fallback is not pinned to a stable config the way mirrored mode is).
3. On pfSense, ensure the LAN interface doesn't have a stricter-than-default gateway/route
   assumption blocking the return path (rarely an issue on a fresh install, worth checking if
   this fallback path is unreliable).

## Install prerequisites inside WSL

```bash
sudo apt update
sudo apt install -y ansible openssl git rsync samba-common-bin python3 python3-pip openssh-client
ansible --version   # confirm ansible-core 2.16+, per docs/DeploymentGuide.md
```

`samba-common-bin` is what provides the `samba-tool` CLI on a non-DC host — needed if you want
to run `docker/mail/scripts/enable-spam-protection.sh` or any ad-hoc `samba-tool dns`/`user`
command from your control host rather than SSHing into `samba-dc01` for every one.

## Clone the repo inside the Linux filesystem, not `/mnt/c/...`

```bash
# Inside WSL - NOT under /mnt/c/Users/...
cd ~
git clone <this-repo-url> lab-small-business
cd lab-small-business
```

Working from `/mnt/c/Users/<you>/...` (the Windows filesystem, mounted into WSL) works, but is
noticeably slower for anything that touches many small files (`ansible-playbook` runs,
`git status` on a repo this size) and can produce confusing file-permission behavior, since
`/mnt/c` maps NTFS permissions onto POSIX in a lossy way. Cloning into WSL's own ext4
filesystem (`~/lab-small-business`) avoids both problems and matches how the lab VMs
themselves see files.

If you also want to edit the same checkout from Windows-native tools occasionally, that's what
the VS Code Remote-WSL integration below is for — you get a normal Windows-feeling editor
window, but the files stay on the fast, correctly-permissioned Linux side.

## VS Code integration

Install the `ms-vscode-remote.remote-wsl` extension (listed in this repo's
[`.vscode/extensions.json`](../.vscode/extensions.json)), then from a WSL terminal inside the
cloned repo:

```bash
code .
```

This opens VS Code running as a Windows application but connected to your WSL filesystem and
using WSL as the integrated terminal — so `redhat.ansible`, `timonwong.shellcheck`, and every
other repo-recommended extension that needs a real Linux/Python/shell environment behaves
correctly, without you needing a second, differently-configured editor setup.

## SSH from WSL to the lab VMs

Standard OpenSSH, same as any Linux control host:

```bash
ssh-keygen -t ed25519 -C "wsl-control-host"
ssh-copy-id labadmin@samba-dc01.lab.internal   # or samba-dc01's DHCP/static IP before DNS is fully live
```

Add the lab hosts to `~/.ssh/config` inside WSL if you want short aliases — this is a normal
`~/.ssh/config`, nothing lab-specific about it.

## Verification checklist

Before running anything from [docs/DeploymentGuide.md](DeploymentGuide.md) steps 3+:

```bash
ping -c 2 10.10.10.1                        # pfSense reachable
ansible --version                           # ansible-core 2.16+
openssl version                             # OpenSSL 3.x (pki/scripts requires this)
ssh -o BatchMode=yes samba-dc01.lab.internal true && echo "SSH OK"
```

If the ping fails, revisit [Networking](#networking-the-part-that-actually-trips-people-up)
above before anything else — every subsequent step depends on it.

## What WSL2 is _not_ used for in this lab

Worth being explicit: WSL2 here is your **Ansible control node and script runner**, not a
Docker host. `docker01` and `authentik01` are separate Ubuntu VMs running the actual
`docker compose` stacks — you don't need Docker Desktop or a WSL2 Docker backend for this repo
to work. If you'd like to test a `docker-compose.yml` locally before deploying it (e.g. while
developing a new stack under `docker/`), installing Docker inside WSL2 or using Docker Desktop
with WSL2 integration is a reasonable convenience, but it's optional and separate from the
lab's actual deployment target.

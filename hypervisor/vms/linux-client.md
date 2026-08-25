# Linux Desktop Client / Control Host — `linux-client01`

| Spec | Value                                        |
| ---- | -------------------------------------------- |
| vCPU | 2                                            |
| RAM  | 4096 MB                                      |
| Disk | 40 GB (thin)                                 |
| NIC  | LAN Segment `LAN-LAB`                        |
| ISO  | Ubuntu Desktop 24.04 LTS                     |
| IP   | DHCP (`10.10.10.100-199`, served by pfSense) |

Built by hand, right after pfSense — no PowerShell script creates this VM. It plays two roles:
it's the **control host** that drives every scripted step from here on (Ansible, the PKI
scripts, `samba-tool`), replacing the need for WSL2 on the Windows host; and later, once AD
exists, it also joins the domain as a lab endpoint like any other client.

## Build + install

1. **File > New Virtual Machine**, custom hardware: 2 vCPU, 4096 MB RAM, 40 GB disk (thin
   provisioned), Ubuntu Desktop 24.04 ISO attached, single NIC on the `LAN-LAB` LAN Segment
   (already exists once pfSense's second NIC is set up — pick it from the same network
   dropdown, don't create it again).
2. Install interactively (Ubuntu Desktop's installer is graphical; unattended desktop installs
   are out of scope for a lab teaching manual desktop use). It gets a DHCP lease from pfSense.

## Set up as the control host

```bash
sudo apt update && sudo apt install -y ansible openssl git rsync samba-common-bin whois \
    python3 python3-pip openssh-client
git clone <this-repo-url> ~/lab-small-business
cd ~/lab-small-business
ansible --version   # confirm ansible-core 2.16+
```

From here on, every `ansible-playbook`, `openssl`, and `samba-tool` command in
[docs/DeploymentGuide.md](../../docs/DeploymentGuide.md) runs from this VM.

## Domain join (later — once AD exists)

```bash
sudo samba/scripts/join-linux-client.sh
```

Then run [`ansible/playbooks/05-pki-trust.yml`](../../ansible/playbooks/05-pki-trust.yml)
against this host (or follow the manual `update-ca-certificates` steps in
[docs/PKI.md](../../docs/PKI.md#trust-deployment)) so HTTPS to `*.lab.internal` is trusted
without a browser warning.

See [docs/StudentLabManual.md](../../docs/StudentLabManual.md) for the exercises students run
from this VM.

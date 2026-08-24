# Linux Desktop Client — `linux-client01`

| Spec | Value                                       |
| ---- | ------------------------------------------- |
| vCPU | 2                                           |
| RAM  | 4096 MB                                     |
| Disk | 40 GB (thin)                                |
| NIC  | `VMnet2`                                    |
| ISO  | Ubuntu Desktop 24.04 LTS                    |
| IP   | DHCP (`10.10.0.100-199`, served by pfSense) |

Install interactively (Ubuntu Desktop's installer is graphical; unattended desktop installs
are out of scope for a lab teaching manual desktop use). After first boot:

```bash
sudo apt update && sudo apt install -y whois
sudo samba/scripts/join-linux-client.sh
```

Then run [`ansible/playbooks/05-pki-trust.yml`](../../ansible/playbooks/05-pki-trust.yml)
against this host (or follow the manual `update-ca-certificates` steps in
[docs/PKI.md](../../docs/PKI.md#trust-deployment)) so HTTPS to `*.lab.internal` is trusted
without a browser warning.

See [docs/StudentLabManual.md](../../docs/StudentLabManual.md) for the exercises students run
from this VM.

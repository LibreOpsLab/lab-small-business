# Federation Topology (Multi-Business)

See [docs/MultiBusiness.md](../docs/MultiBusiness.md) for the full workflow. This diagram
shows two independently-deployed businesses bridged by an IPSec site-to-site tunnel, plus a
remote user reaching one business over WireGuard — both mechanisms scoped to specific
hosts/ports rather than full subnet trust.

```mermaid
flowchart TB
    subgraph BizA["Business A — acme.internal (10.10.0.0/24)"]
        PFA["pfSense A\nWAN + LAN"]
        DCA["samba-dc01\n10.10.0.10"]
        APPA["docker01\n10.10.0.20"]
        AKA["authentik01\n10.10.0.30"]
    end

    subgraph BizB["Business B — bizb.internal (10.20.0.0/24)"]
        PFB["pfSense B\nWAN + LAN"]
        DCB["samba-dc01\n10.20.0.10"]
        APPB["docker01\n10.20.0.20"]
        AKB["authentik01\n10.20.0.30"]
    end

    REMOTE["Remote user\n(student01, off-site laptop)"]

    PFA <==>|"IPSec IKEv2 site-to-site\nPSK, AES256-GCM/SHA256\nscoped: only 443->docker01, not full subnet"| PFB
    REMOTE ==>|"WireGuard\nAllowedIPs: docker01, authentik01 only"| PFA

    PFA --- DCA
    PFA --- APPA
    PFA --- AKA
    PFB --- DCB
    PFB --- APPB
    PFB --- AKB

    classDef fw fill:#f8d7da,stroke:#c0392b,color:#000
    classDef infra fill:#d6eaf8,stroke:#2874a6,color:#000
    classDef remote fill:#d5f5e3,stroke:#1e8449,color:#000
    class PFA,PFB fw
    class DCA,APPA,AKA,DCB,APPB,AKB infra
    class REMOTE remote
```

## What crosses the tunnel vs. what doesn't

| Crosses the IPSec tunnel | Does not cross |
|---|---|
| Packets to the specific host:port pairs each side's scoped firewall rule allows (see [MultiBusiness.md#scoped-firewall-rules-not-full-subnet-trust](../docs/MultiBusiness.md#scoped-firewall-rules-not-full-subnet-trust)) | PKI trust — each business keeps its own Root/Issuing CA; the other side's certs show as untrusted until deliberately imported |
| — | AD/Kerberos federation — Business A's Authentik does not federate Business B's Samba AD |
| — | DNS — each business's DNS remains authoritative only for its own domain; there is no shared resolution unless [LabInternet.md](../docs/LabInternet.md) is layered on top |

This gap between "network reachable" and "trusted/federated" is intentional and is the
teaching point of [docs/MultiBusiness.md](../docs/MultiBusiness.md) — closing that gap
deliberately, rather than by default, is what [docs/LabInternet.md](../docs/LabInternet.md)
is for.

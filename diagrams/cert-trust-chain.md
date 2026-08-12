# Certificate Trust Chain

A two-tier internal PKI is used: an **offline Root CA** that only ever signs the Intermediate
CA's certificate and CRL, and an **online Issuing CA** that signs all leaf/server certificates.
This mirrors enterprise practice and lets the Root CA's private key remain offline (exported to
removable media after each Intermediate operation) for the lifetime of the lab.

```mermaid
flowchart TD
    ROOT["LAB Root CA\n(Offline)\nCN=LAB Root CA\nValidity: 20 years\nKey: kept offline / air-gapped VM"]
    INT["LAB Issuing CA\n(Online)\nCN=LAB Issuing CA\nValidity: 10 years\nHosted on docker01 / pki tooling"]
    LEAF1["cloud.lab.internal\n(NextCloud)"]
    LEAF2["docs.lab.internal\n(OnlyOffice)"]
    LEAF3["mail.lab.internal\n(Dovecot)"]
    LEAF4["auth.lab.internal\n(Authentik)"]
    LEAF5["samba-dc01.lab.internal\n(LDAPS)"]

    ROOT -->|signs| INT
    INT -->|signs| LEAF1
    INT -->|signs| LEAF2
    INT -->|signs| LEAF3
    INT -->|signs| LEAF4
    INT -->|signs| LEAF5

    classDef root fill:#f8d7da,stroke:#c0392b,color:#000
    classDef int fill:#fdebd0,stroke:#b9770e,color:#000
    classDef leaf fill:#d5f5e3,stroke:#1e8449,color:#000
    class ROOT root
    class INT int
    class LEAF1,LEAF2,LEAF3,LEAF4,LEAF5 leaf
```

## Trust distribution

```mermaid
flowchart LR
    ROOTCERT["lab-root-ca.crt"]
    subgraph Windows
        GPO["Group Policy\nComputer Config > Policies >\nWindows Settings > Security Settings >\nPublic Key Policies > Trusted Root CAs"]
    end
    subgraph Linux
        UCC["/usr/local/share/ca-certificates/\n+ update-ca-certificates"]
    end
    subgraph Docker
        MNT["Bind-mounted into containers:\n/etc/ssl/certs/lab-root-ca.crt"]
    end

    ROOTCERT --> GPO
    ROOTCERT --> UCC
    ROOTCERT --> MNT
```

Both the Root CA certificate and the Issuing CA certificate are distributed to trust stores
(the full chain), while only the Root CA certificate is marked as a **trust anchor**. See
[PKI.md](../docs/PKI.md) for the full certificate lifecycle and distribution automation
(`pki/scripts/`, `pki/gpo/deploy-root-ca.ps1`, `ansible/roles/pki_trust`).

# Authentication Flow (Kerberos / LDAP)

Domain members (Linux via SSSD, Windows natively) authenticate directly against Samba AD using
Kerberos for interactive/service logon and LDAP for identity lookups. Authentik federates the
same directory for web applications rather than maintaining a separate user store.

```mermaid
sequenceDiagram
    participant U as User
    participant C as Domain Client\n(Linux SSSD / Windows)
    participant DC as samba-dc01\n(KDC / LDAP / DNS)
    participant APP as Application\n(e.g. file share, RDP)

    U->>C: Enter LAB\username + password
    C->>DC: DNS SRV lookup _kerberos._udp.lab.local
    DC-->>C: KDC = samba-dc01.lab.local
    C->>DC: AS-REQ (request TGT)
    DC-->>C: AS-REP (TGT, encrypted with user key)
    C->>DC: TGS-REQ (request service ticket for APP)
    DC-->>C: TGS-REP (service ticket)
    C->>APP: AP-REQ (present service ticket)
    APP-->>C: AP-REP (mutual auth OK)
    APP->>DC: LDAP bind/query (group membership, attributes)
    DC-->>APP: User attributes + group SIDs
    APP-->>U: Session established (RBAC applied from group membership)
```

## Notes

- Linux clients resolve the realm via SSSD (`sssd.conf`, see
  [samba/templates](../samba/templates)) using `krb5` + `ldap` providers against `samba-dc01`.
- Windows clients use the native Kerberos SSO stack once domain-joined; no additional
  configuration is required beyond DNS pointing at `10.10.0.10`.
- Service accounts (e.g. Authentik's LDAP bind account) use a dedicated low-privilege account
  (`svc-authentik`) rather than `administrator`, per least-privilege ([Security.md](../docs/Security.md)).
- Ticket lifetime and renewal policy are set via `samba-tool domain passwordsettings` and
  `msDS-*` attributes — see [SambaAdmin.md](../docs/SambaAdmin.md).

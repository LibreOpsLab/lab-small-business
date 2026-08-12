# OIDC Authentication Flow (Authentik → Application)

Applications that support OpenID Connect (NextCloud, and Authentik's own admin/user portal)
delegate authentication to Authentik using the Authorization Code flow with PKCE. Authentik in
turn resolves the user's identity from Samba AD via its LDAP source, so there is a single
source of truth for identity even though two protocols (Kerberos/LDAP and OIDC) are in play.

```mermaid
sequenceDiagram
    participant U as User Browser
    participant APP as Application\n(cloud.lab.internal)
    participant AK as Authentik\n(auth.lab.internal)
    participant DC as samba-dc01\n(LDAP Source)

    U->>APP: GET https://cloud.lab.internal
    APP-->>U: 302 Redirect to Authentik\n(authorize endpoint + PKCE challenge)
    U->>AK: GET /application/o/authorize/?client_id=...&code_challenge=...
    AK-->>U: Login form (or SSO session reuse)
    U->>AK: Submit LAB\username + password (+MFA if enrolled)
    AK->>DC: LDAP bind as user (via LDAP Source)
    DC-->>AK: Bind success + group memberships
    AK-->>U: 302 Redirect to APP redirect_uri?code=...
    U->>APP: GET redirect_uri?code=...
    APP->>AK: POST /application/o/token/ (code + code_verifier)
    AK-->>APP: id_token + access_token + refresh_token
    APP->>AK: GET /application/o/userinfo/ (access_token)
    AK-->>APP: Claims (sub, email, groups, name)
    APP-->>U: Authenticated session (role mapped from `groups` claim)
```

## Claim / group mapping

| Authentik Group | OIDC `groups` claim value | Application role mapping         |
| --------------- | ------------------------- | -------------------------------- |
| IT-Admins       | `IT-Admins`               | NextCloud admin, Authentik admin |
| Docker-Admins   | `Docker-Admins`           | Traefik dashboard, Portainer     |
| Lecturers       | `Lecturers`               | NextCloud group folder owner     |
| Students        | `Students`                | NextCloud standard user          |

Group sync from Samba AD into Authentik is configured in
[authentik/blueprints/ldap-source.yaml](../authentik/blueprints/ldap-source.yaml); the OIDC
providers and scope/claim mappings are in
[authentik/blueprints/oidc-nextcloud.yaml](../authentik/blueprints/oidc-nextcloud.yaml) and
[authentik/blueprints/oidc-onlyoffice.yaml](../authentik/blueprints/oidc-onlyoffice.yaml).

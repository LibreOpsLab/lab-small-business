# PKI — Internal Certificate Authority

## Design

A two-tier CA hierarchy, matching enterprise practice:

1. **LAB Root CA** — offline, self-signed, 4096-bit RSA, 20-year validity. Signs only the
   Intermediate CA certificate and periodic CRLs. Its private key is generated once by
   [`pki/scripts/00-init-root-ca.sh`](../pki/scripts/00-init-root-ca.sh) and should be moved to
   offline storage (USB key, or a powered-off VM snapshot) after the Intermediate CA is issued.
2. **LAB Issuing CA** — online, 4096-bit RSA, 10-year validity, signed by the Root CA. Issues
   all leaf/server certificates day-to-day. Lives on whichever host runs the PKI scripts
   (recommended: `docker01`, under `/opt/lab-pki`).

See [cert-trust-chain.md](../diagrams/cert-trust-chain.md) for the visual chain and trust
distribution diagram.

## Directory layout (generated at runtime, gitignored)

```text
pki/
├── root-ca/
│   ├── private/ca.key.pem        (0400, offline after bootstrap)
│   ├── certs/ca.cert.pem
│   ├── db/ (index.txt, serial, crlnumber)
│   └── crl/ca.crl.pem
├── intermediate-ca/
│   ├── private/intermediate.key.pem (0400)
│   ├── certs/intermediate.cert.pem
│   ├── certs/ca-chain.cert.pem   (intermediate + root, for server bundles)
│   ├── db/
│   └── crl/intermediate.crl.pem
└── issued/
    └── <cn>/ (cert.pem, chain.pem, fullchain.pem, key.pem, csr.pem)
```

Only `pki/openssl/*.cnf` (the OpenSSL policy configs) and the scripts themselves are committed;
all generated key material is excluded via [`.gitignore`](../.gitignore).

## Scripts

| Script                                                                    | Purpose                                                                                         |
| ------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------- |
| [`00-init-root-ca.sh`](../pki/scripts/00-init-root-ca.sh)                 | One-time: generates Root CA key + self-signed cert, initialises the OpenSSL CA database.        |
| [`01-init-intermediate-ca.sh`](../pki/scripts/01-init-intermediate-ca.sh) | One-time: generates Issuing CA key + CSR, signs it with the Root CA, builds the chain bundle.   |
| [`02-issue-server-cert.sh`](../pki/scripts/02-issue-server-cert.sh)       | Repeatable: issues a leaf certificate for a given CN/SAN list, signed by the Issuing CA.        |
| [`03-renew-cert.sh`](../pki/scripts/03-renew-cert.sh)                     | Re-issues a certificate ahead of expiry, reusing the existing key unless `--new-key` is passed. |
| [`04-revoke-cert.sh`](../pki/scripts/04-revoke-cert.sh)                   | Revokes a certificate by serial or CN and regenerates the Issuing CA's CRL.                     |

All scripts source [`pki/scripts/lib/common.sh`](../pki/scripts/lib/common.sh) for shared
paths, colour logging, and `openssl` version checks, and are safe to re-run (they check for
existing material before overwriting).

## Bootstrap sequence

```bash
cd pki/scripts
./00-init-root-ca.sh                 # creates pki/root-ca/*
./01-init-intermediate-ca.sh         # creates pki/intermediate-ca/*, signed by root

# move pki/root-ca/private/ca.key.pem to offline storage now — the rest of the
# lab never needs it again, only pki/root-ca/certs/ca.cert.pem (public)

./02-issue-server-cert.sh --cn cloud.lab.local  --san DNS:cloud.lab.local
./02-issue-server-cert.sh --cn docs.lab.local   --san DNS:docs.lab.local
./02-issue-server-cert.sh --cn mail.lab.local   --san DNS:mail.lab.local
./02-issue-server-cert.sh --cn auth.lab.local   --san DNS:auth.lab.local
./02-issue-server-cert.sh --cn samba-dc01.lab.local --san "DNS:samba-dc01.lab.local,DNS:lab.local"
```

`ansible/playbooks/05-pki-trust.yml` (role: `pki_trust`) then distributes
`pki/root-ca/certs/ca.cert.pem` and `pki/intermediate-ca/certs/intermediate.cert.pem` to every
Linux host and bind-mounts them into containers; see the next section for Windows.

## Trust deployment

- **Windows (GPO):** [`pki/gpo/deploy-root-ca.ps1`](../pki/gpo/deploy-root-ca.ps1) imports the
  Root CA certificate into a domain GPO's
  `Computer Configuration > Policies > Windows Settings > Security Settings > Public Key
Policies > Trusted Root Certification Authorities` store and the Issuing CA into
  `Intermediate Certification Authorities`, then links the GPO to the domain. Run once from an
  elevated PowerShell session on `samba-dc01` (or an RSAT-equipped admin workstation) after
  the Intermediate CA is issued.
- **Linux:** `ansible/roles/pki_trust` copies both certs to
  `/usr/local/share/ca-certificates/` and runs `update-ca-certificates`. Applied by
  `05-pki-trust.yml` to every Linux host in inventory (client, docker server, SSSD-joined
  machines).
- **Docker:** each Compose stack under `docker/` bind-mounts
  `pki/intermediate-ca/certs/ca-chain.cert.pem` read-only into containers that terminate TLS
  (Traefik) or validate LDAPS (Authentik), e.g.
  `./certs/ca-chain.cert.pem:/etc/ssl/certs/lab-ca-chain.pem:ro`.

## Renewal

Leaf certificates are issued with a 397-day validity (the practical maximum most browsers
still honour) via `02-issue-server-cert.sh`. Run `03-renew-cert.sh --cn <name>` any time inside
that window; it re-signs using the existing CSR/key by default so downstream configs referring
to the same key path don't need updates. A cron/systemd-timer example lives in
[`ansible/roles/pki_trust/tasks`](../ansible/roles/pki_trust/tasks) (`renew-check.timer`,
disabled by default — enable once the lab is stable) that runs a dry-run expiry check weekly.

## Revocation

`04-revoke-cert.sh --cn cloud.lab.local` (or `--serial <hex>`) marks the certificate revoked in
the Issuing CA's OpenSSL database and regenerates `intermediate.crl.pem`. The CRL is served by
Traefik at `http://auth.lab.local/crl/intermediate.crl.pem` (see
[`docker/reverse-proxy/traefik/dynamic.yml`](../docker/reverse-proxy/traefik/dynamic.yml)) and
should also be re-pushed to Linux/Windows trust stores if you rely on CRL checking rather than
OCSP (this lab does not stand up an OCSP responder — CRL only, refreshed on each revoke).

## Key sizes & algorithms

RSA 4096 was chosen over EC for teaching clarity (openssl CLI output/inspection is more
familiar to students with RSA) at the cost of slightly slower TLS handshakes — acceptable for a
homelab. If you want to teach ECDSA, `pki/openssl/intermediate-ca.cnf` documents the
`default_md`/`default_bits` knobs to flip.

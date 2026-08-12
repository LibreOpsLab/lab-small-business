# Class Registry

A small web app the lecturer runs so students can self-register their business's domain +
subnet, get their edge reverse proxy's TLS certificate signed by a shared "class CA," and get
their subdomain NS-delegated in a real `lab.internet` DNS zone — see
[docs/ClassRegistry.md](../../docs/ClassRegistry.md) for the full design and workflow. This is
part of the optional, advanced federation/interop layer: **the base lab runs completely fine
without ever standing this up.**

## Contents

- [`app/`](app/) — the Flask registry (single small app, SQLite storage, no JS framework).
- [`bind/`](bind/) — BIND9 config + the `lab.internet` zone (rewritten by the app on every
  registration).
- [`ca/`](ca/) — the single-tier "class CA" used only to sign business edge-proxy certs.
- [`scripts/init-registry.sh`](scripts/init-registry.sh) — one-time lecturer setup.

## Quick start (lecturer)

```bash
cd federation/class-registry
./scripts/init-registry.sh --ns-ip <this-host's-IP-students-can-reach>
docker compose up -d
```

Then give students: the registry URL (`http://<ns-ip>:8080`) and the generated
`CLASS_REGISTRY_TOKEN` (printed by `init-registry.sh`, also in `.env`).

## Quick start (student)

See [`federation/scripts/register-with-class.sh`](../scripts/register-with-class.sh) and
[`federation/scripts/request-class-cert.sh`](../scripts/request-class-cert.sh), or just use the
registry's web form directly.

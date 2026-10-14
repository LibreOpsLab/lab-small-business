# RMM: Remote Monitoring and Management

An **RMM** is the console an IT service desk lives in: an agent on every machine that reports
health, applies patches, runs scripts and offers remote access, all from one web page. This lab
manages machines with code (Ansible, Group Policy) and watches them with Prometheus, Grafana and
Loki. An RMM is the commercial-world alternative, and the one most small IT providers actually use,
so a Junior Server Engineer should have seen one.

**Status in this repo: an optional evaluation, not part of the base lab.** Nothing here depends on it.

## Candidate: Breeze RMM (Community)

Chosen for evaluation: [Breeze RMM](https://breezermm.com/) ([source](https://github.com/LanternOps/breeze)).

What its own documentation states:

| Topic | What the project says |
|---|---|
| Licence | Core is AGPL-3.0. A separate `ee/` directory is under a **commercial licence** that needs an agreement for production use |
| Self-hosting | Docker Compose, with a guided setup script that generates `.env` and `docker-compose.yml` |
| Stack | PostgreSQL, Redis, an API, a web front end, a TURN relay for remote sessions; Caddy as the default proxy (an external proxy such as Nginx Proxy Manager is also offered) |
| Agents | One binary for Windows, Linux and macOS |
| Patching | Inventory, approve and deploy OS and application patches, with maintenance windows and update rings, and compliance reports |
| Also | Scripting, remote access, alerts, device management |
| Sign-in | Passwords (Argon2id) and TOTP MFA. **SSO (SAML and OIDC) is implemented but "awaiting field validation"** |
| Maturity | No stable or beta statement for the project; fast-moving (release numbers in the 0.1xx range). The hosted offering is in public beta |

What it does **not** document: server CPU, RAM or disk needs; which agent OS versions are
supported; which free features are limited. Find those out before committing.

## Where it would fit

| Need | In the lab today | With an RMM |
|---|---|---|
| Patch Windows in rings | Ansible `win_updates` ([PatchManagement.md](PatchManagement.md)) | Patch policies and maintenance windows in a console |
| Patch third-party apps | A gap | Often covered |
| Run a script on many machines | Ansible | Scripts module |
| Help a user remotely | None | Built-in remote session |
| See machine health | Prometheus and Grafana | Built-in alerts |
| Everything in Git, reviewable | Yes | Mostly in the database |

The lab's methods are better for *teaching* because everything is visible code. An RMM is better
for *running a service desk* because it has a console and remote access. Knowing why is the lesson.

## Constraints on trying it here

- **Memory.** A Postgres, Redis, API and web stack is not small, and the 32 GB lab PC is already
  full ([sizing](../scenarios/2-nested-proxmox/README.md#reference-lab-pc-and-sizing)). Try it on
  native Proxmox hardware or a shared class server, or swap it in for another VM for a week.
- **Certificates and the Internet.** The default proxy gets certificates from Let's Encrypt, which
  needs a public name. In this isolated lab use an external proxy and a certificate from the lab
  CA. Agents must verify that certificate; never turn verification off.
- **Single sign-on.** Do not put forward-auth in front of the agent endpoints: agents cannot log
  in through a browser. If SSO is wanted, use the project's OIDC support against Authentik, and
  only after it has been validated.
- **Licence.** Confirm that your use of the `ee/` features is covered before relying on them. The
  AGPL core is free to run; the commercial directory is not necessarily.
- **Trust.** An agent that can run scripts as SYSTEM on every machine is a very powerful thing to
  install. The RMM server becomes the most valuable target in the estate: harden it, patch it,
  back it up, and monitor it like a domain controller.

## If you try it

1. Build a VM (`rmm01`, outside the base IP plan) and install Docker.
2. In an empty directory, fetch the project's `guided-setup.sh` from its repository, read it, and
   run it. It writes the `.env` and Compose file; read both before starting.
3. Put it behind Traefik or another proxy using a lab-CA certificate, add a DNS name, and a
   Prometheus probe ([Monitoring.md](Monitoring.md#adding-a-service)).
4. Install the agent on `winsrv01` and a Linux VM. Compare the same patch run done by Ansible and
   by the RMM. Which gave better evidence? Which would you rather inherit?
5. Write up what you would and would not trust it with.

## Other options to compare

Open-source and commercial RMMs differ mainly in maturity, licence and what is paywalled.
Other open options include NetLock RMM and MeshCentral (remote access focused). Commercial
products such as NinjaOne, Datto and ConnectWise are what most service providers pay for. Don't
treat this page as an endorsement: the exercise is to judge one against a checklist, which is
the same skill as choosing any tool.

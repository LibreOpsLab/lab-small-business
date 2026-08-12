# Stirling PDF

Self-hosted PDF toolkit (merge/split/OCR/convert/sign) at `https://pdf.lab.internal` — the
lab's Adobe Acrobat replacement. See [docs/DesktopApps.md](../../docs/DesktopApps.md) for the
desktop-shortcut ("pin as an app") experience.

## Access control: forward-auth, not OIDC

Stirling PDF has no native OIDC/SSO integration, so unlike NextCloud/WordPress it isn't gated
by a client ID/secret pair — instead, `docker-compose.yml` sets `DOCKER_ENABLE_SECURITY=false`
(disabling Stirling's own built-in login entirely) and Traefik's `authentik-forwardauth`
middleware ([`../reverse-proxy/traefik/dynamic.yml`](../reverse-proxy/traefik/dynamic.yml))
asks Authentik's embedded outpost to authenticate every request before it ever reaches the
container. This is configured by
[`authentik/blueprints/proxy-stirling-pdf.yaml`](../../authentik/blueprints/proxy-stirling-pdf.yaml)
— see that file's trailing comment for the one manual verification step (confirming the
provider landed on Authentik's embedded outpost) that blueprint application doesn't
100%-reliably automate.

This is a deliberately different integration pattern from NextCloud/WordPress, useful for
teaching the distinction: OIDC needs the app to cooperate (implement the protocol);
forward-auth needs only a reverse proxy in front of it, so it works for apps — like this one —
that were never built with SSO in mind.

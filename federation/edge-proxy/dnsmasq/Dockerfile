# Small, transparent dnsmasq build (same philosophy as docker/mail/postfix's hand-configured
# image) answering authoritatively for this business's delegated <name>.lab.internet zone.
# See docs/ClassRegistry.md#dns-design.
FROM debian:bookworm-slim

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends dnsmasq \
    && rm -rf /var/lib/apt/lists/* \
    && rm -f /etc/dnsmasq.conf

COPY dnsmasq.conf.template /etc/dnsmasq.conf.template
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 53/udp 53/tcp
ENTRYPOINT ["/entrypoint.sh"]

#!/bin/sh
set -eu
: "${BUSINESS_NAME:?Set BUSINESS_NAME (your registered class-registry name, e.g. acme)}"
: "${EDGE_IP:?Set EDGE_IP (this edge proxy reachable IP - same value given to the class registry)}"

sed -e "s/__BUSINESS_NAME__/${BUSINESS_NAME}/g" -e "s/__EDGE_IP__/${EDGE_IP}/g" \
  /etc/dnsmasq.conf.template > /etc/dnsmasq.conf

exec dnsmasq --keep-in-foreground --log-facility=- --conf-file=/etc/dnsmasq.conf

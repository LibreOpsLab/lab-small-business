#!/bin/sh
# Runs inside the wordpress:cli image as the wp-init service in docker-compose.yml.
# Idempotent: skips wp core install if WordPress is already installed. Installs and
# activates the OpenID Connect Generic plugin so configure-oidc-plugin.sh (run from the
# host, after Authentik's WordPress OIDC provider exists) has something to configure.
set -eu

cd /var/www/html

echo "[wp-init] Waiting for the database to accept connections..."
for i in $(seq 1 30); do
  wp db check --path=/var/www/html --allow-root >/dev/null 2>&1 && break
  sleep 2
done

if wp core is-installed --allow-root >/dev/null 2>&1; then
  echo "[wp-init] WordPress already installed — skipping core install."
else
  echo "[wp-init] Running wp core install..."
  wp core install \
    --url="${WORDPRESS_SITE_URL}" \
    --title="${WORDPRESS_SITE_TITLE}" \
    --admin_user="${WORDPRESS_ADMIN_USER}" \
    --admin_password="${WORDPRESS_ADMIN_PASSWORD}" \
    --admin_email="${WORDPRESS_ADMIN_EMAIL}" \
    --skip-email \
    --allow-root
fi

echo "[wp-init] Installing/activating the OpenID Connect Generic plugin (SSO via Authentik - optional, configured separately)..."
wp plugin install daggerhart-openid-connect-generic --activate --allow-root || \
  echo "[wp-init] Plugin install failed (offline / plugin repo unreachable?) — retry later with: docker compose exec wp-init wp plugin install daggerhart-openid-connect-generic --activate --allow-root"

echo "[wp-init] Setting permalinks to a sane default (post name) instead of ugly query-string URLs..."
wp rewrite structure '/%postname%/' --allow-root
wp rewrite flush --allow-root

echo "[wp-init] Done. Run docker/wordpress/scripts/configure-oidc-plugin.sh once Authentik is bootstrapped to wire up SSO."

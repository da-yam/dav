#!/bin/bash

set -euo pipefail

# shellcheck disable=SC1091
source /opt/dayam/config.conf

HOST=dav
FQDN=$HOST.$LINODE_DOMAIN
EMAIL=admin@$LINODE_DOMAIN

LINODE_API_TOKEN="$LINODE_API_TOKEN" linode-dns \
  --domain "$LINODE_DOMAIN" \
  --name "$HOST" \
  --ipv4 "$LINODE_IPV4" \
  --ipv6 "$LINODE_IPV6"

apt-get install -yqq apache2-utils certbot nginx python3-certbot-nginx \
  radicale uwsgi uwsgi-plugin-python3

[ -f "/etc/letsencrypt/live/$FQDN/fullchain.pem" ] ||
  certbot certonly --nginx --email "$EMAIL" --agree-tos --no-eff-email \
    --force-renewal --domain "$FQDN"

ln -sft /etc/uwsgi/apps-enabled/ ../apps-available/radicale.ini
systemctl restart uwsgi

touch /etc/nginx/htpasswd
chmod 640 /etc/nginx/htpasswd
chown root:www-data /etc/nginx/htpasswd
htpasswd -bc /etc/nginx/htpasswd "$RADICALE_USERNAME" "$RADICALE_PASSWORD"

cat <<EOF >/etc/nginx/sites-available/dav
server {
  listen 80;
  listen [::]:80;
  listen 443 ssl;
  listen [::]:443 ssl;
  server_name $FQDN;

  include /etc/letsencrypt/options-ssl-nginx.conf;
  ssl_certificate /etc/letsencrypt/live/$FQDN/fullchain.pem;
  ssl_certificate_key /etc/letsencrypt/live/$FQDN/privkey.pem;

  if (\$scheme != "https") {
    return 301 https://\$host\$request_uri;
  }

  location / {
    auth_basic "Radicale";
    auth_basic_user_file /etc/nginx/htpasswd; 
    include    uwsgi_params;
    uwsgi_pass unix:/var/run/uwsgi/app/radicale/socket;
    uwsgi_param REMOTE_USER \$remote_user;
  }
}
EOF

rm -f /etc/nginx/sites-enabled/default
ln -sft /etc/nginx/sites-enabled/ ../sites-available/dav
systemctl restart nginx

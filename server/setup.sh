#!/usr/bin/env bash
# Runs ON the server as root (deploy.sh sends it with the files in /tmp/clmr).
# Safe to run again: makes the clmr user, installs the game and the service,
# opens the firewall for SSH and the lobbies, turns off password logins.
# The browser build's secure WebSockets (wss, lobbies.json "ws_port") need a
# certificate for the server's hostname: once, by hand (it accepts Let's
# Encrypt's terms), `certbot certonly --standalone -d <hostname>`; this then
# copies it where the lobbies (user clmr) can read it, now and on renewal.
set -euo pipefail
src=/tmp/clmr
id clmr >/dev/null 2>&1 || useradd --system --home-dir /opt/clmr --shell /usr/sbin/nologin clmr
mkdir -p /opt/clmr
install -m 755 "$src/clmr_server.x86_64" /opt/clmr/clmr_server.x86_64.new
mv -f /opt/clmr/clmr_server.x86_64.new /opt/clmr/clmr_server.x86_64
install -m 644 "$src/lobbies.json" /opt/clmr/lobbies.json
chown -R clmr:clmr /opt/clmr
install -m 644 "$src/clmr-lobbies.service" /etc/systemd/system/clmr-lobbies.service
systemctl daemon-reload
systemctl enable clmr-lobbies >/dev/null
# Firewall: SSH and the two lobbies' UDP ports only.
if ! command -v ufw >/dev/null; then apt-get install -y ufw >/dev/null; fi
ufw allow 22/tcp >/dev/null
ufw delete allow 47197:47199/udp >/dev/null 2>&1 || true
ufw allow 47197:47198/udp >/dev/null
# certbot's renewal (80), the lobbies' wss (443, 8443: IONOS's own firewall
# passes these and not the 47xxx TCP ports).
ufw allow 80/tcp >/dev/null
ufw allow 443/tcp >/dev/null
ufw allow 8443/tcp >/dev/null
ufw --force enable >/dev/null
mkdir -p /etc/letsencrypt/renewal-hooks/deploy /etc/clmr/tls
cat > /etc/letsencrypt/renewal-hooks/deploy/restart-clmr.sh <<'HOOK'
#!/bin/sh
# The certificate where the lobbies can read it, then the lobbies restarted.
for d in /etc/letsencrypt/live/*/; do
  if [ -f "$d/fullchain.pem" ]; then
    install -o clmr -g clmr -m 600 "$d/fullchain.pem" /etc/clmr/tls/fullchain.pem
    install -o clmr -g clmr -m 600 "$d/privkey.pem" /etc/clmr/tls/privkey.pem
    break
  fi
done
[ "${1:-}" = "copy-only" ] || systemctl restart clmr-lobbies
HOOK
chmod +x /etc/letsencrypt/renewal-hooks/deploy/restart-clmr.sh
rm -f /etc/clmr/tls/fullchain.pem /etc/clmr/tls/privkey.pem
/etc/letsencrypt/renewal-hooks/deploy/restart-clmr.sh copy-only
# SSH: keys only (the owner's key is installed; root logs in with it).
cat > /etc/ssh/sshd_config.d/10-keys-only.conf <<'CONF'
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin prohibit-password
CONF
sshd -t && systemctl reload ssh
systemctl restart clmr-lobbies
sleep 3
systemctl --no-pager --lines=8 status clmr-lobbies

#!/bin/sh
# Installiert oder aktualisiert den Bociva-Server unter Debian/Ubuntu, etwa in
# einem Proxmox-LXC-Container.
#
#   sh install.sh bociva-server-<version>-linux-x64.tar.gz
#
# Programm in /opt/bociva (die vorige Version in /opt/bociva.old), Daten in
# /var/lib/bociva/data, Schlüssel in /var/lib/bociva/keys, Einstellungen in
# /etc/bociva/bociva.env, systemd-Dienst „bociva“. Vor einem Update werden die
# Daten nach /root/bociva-backup kopiert.
set -eu

SRC="${1:-}"
[ -n "$SRC" ] && [ -f "$SRC" ] || { echo "Aufruf: $0 bociva-server-<version>-linux-<arch>.tar.gz" >&2; exit 64; }
[ "$(id -u)" -eq 0 ] || { echo "Bitte als root ausführen." >&2; exit 1; }
HERE=$(cd "$(dirname "$0")" && pwd)

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
tar -xzf "$SRC" -C "$TMP"
[ -x "$TMP/bundle/bin/server" ] || { echo "Im Archiv fehlt bundle/bin/server." >&2; exit 1; }

id bociva >/dev/null 2>&1 || useradd --system --home /var/lib/bociva --shell /usr/sbin/nologin bociva
install -d -o bociva -g bociva -m 0700 /var/lib/bociva /var/lib/bociva/data /var/lib/bociva/keys
install -d -m 0755 /etc/bociva
[ -f /etc/bociva/bociva.env ] || install -m 0640 -g bociva "$HERE/bociva.env" /etc/bociva/bociva.env

systemctl stop bociva 2>/dev/null || true
if [ -f /var/lib/bociva/data/bociva.db ]; then
  BACKUP="/root/bociva-backup/$(date +%Y%m%d-%H%M%S)"
  install -d -m 0700 "$BACKUP"
  cp -a /var/lib/bociva/data /var/lib/bociva/keys "$BACKUP/"
  echo "Sicherung: $BACKUP"
fi
rm -rf /opt/bociva.new && mkdir -p /opt/bociva.new
cp -R "$TMP/bundle/." /opt/bociva.new/
rm -rf /opt/bociva.old
[ ! -d /opt/bociva ] || mv /opt/bociva /opt/bociva.old
mv /opt/bociva.new /opt/bociva

install -m 0644 "$HERE/bociva.service" /etc/systemd/system/bociva.service
systemctl daemon-reload
systemctl enable --now bociva

ok=0
for _ in 1 2 3 4 5 6 7 8 9 10; do
  sleep 1
  if runuser -u bociva -- env BOCIVA_PORT="$(sed -n 's/^BOCIVA_PORT=//p' /etc/bociva/bociva.env)" /opt/bociva/bin/server --healthcheck; then
    ok=1
    break
  fi
done
if [ "$ok" -eq 1 ]; then
  echo "Bociva läuft."
  # Steht nur im Protokoll, solange es noch kein Konto gibt. Nur der jetzige
  # Start zählt; ältere Starts zeigen sonst einen längst verbrauchten Code.
  INVOCATION=$(systemctl show -p InvocationID --value bociva)
  journalctl --no-pager -o cat "_SYSTEMD_INVOCATION_ID=$INVOCATION" | grep 'Einrichtungscode' | tail -n 1 || true
else
  echo "Bociva startet nicht – siehe: journalctl -u bociva" >&2
  exit 1
fi

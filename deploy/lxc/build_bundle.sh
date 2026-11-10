#!/bin/sh
# Baut das Server-Paket für einen LXC-Container ohne Docker:
# build/bociva-server-<version>-linux-<arch>.tar.gz
#
#   app/tool/build_web.sh               (Weboberfläche, einmal vorher)
#   deploy/lxc/build_bundle.sh [x64|arm64]
set -eu
cd "$(dirname "$0")/../.."
ARCH="${1:-x64}"
case "$ARCH" in
  x64) PLATFORM=linux/amd64 ;;
  arm64) PLATFORM=linux/arm64 ;;
  *) echo "Unbekannte Architektur: $ARCH" >&2; exit 64 ;;
esac
[ -f server/web/index.html ] || { echo "Erst app/tool/build_web.sh ausführen." >&2; exit 1; }
VERSION=$(sed -n "s/^const version = '\(.*\)';/\1/p" server/lib/src/server.dart)
OUT="build/bociva-server-$VERSION-linux-$ARCH"
rm -rf "$OUT" && mkdir -p "$OUT"
docker build --platform "$PLATFORM" --target bundle --output "type=local,dest=$OUT" .
# Keine macOS-Dateiattribute im Archiv.
COPYFILE_DISABLE=1 tar --no-xattrs -czf "$OUT.tar.gz" -C "$OUT" bundle
rm -rf "$OUT"
echo "$OUT.tar.gz"

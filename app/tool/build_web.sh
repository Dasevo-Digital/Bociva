#!/bin/sh
# Baut die Weboberfläche nach server/web. Server und Docker-Image liefern sie
# von dort aus; der Browser lädt nichts von fremden Hosts.
set -eu
cd "$(dirname "$0")/.."
flutter build web --release --no-web-resources-cdn "$@"
rm -rf ../server/web
mkdir -p ../server/web
cp -R build/web/. ../server/web/
python3 - ../server/web <<'PY'
import gzip, os, re, shutil, sys
web = sys.argv[1]
service_worker = os.path.join(web, 'flutter_service_worker.js')
if os.path.exists(service_worker):
    os.remove(service_worker)
kit = os.path.join(web, 'canvaskit')
for name in os.listdir(kit):
    if re.match(r'(skwasm|wimp|experimental_webparagraph)', name):
        path = os.path.join(kit, name)
        shutil.rmtree(path) if os.path.isdir(path) else os.remove(path)
for root, _, files in os.walk(kit):
    for name in files:
        if name.endswith('.symbols'):
            os.remove(os.path.join(root, name))
for root, _, files in os.walk(web):
    for name in files:
        if name.endswith(('.js', '.mjs', '.wasm', '.json', '.html', '.css', '.ttf', '.otf')):
            path = os.path.join(root, name)
            with open(path, 'rb') as src, gzip.open(path + '.gz', 'wb', 9) as dst:
                shutil.copyfileobj(src, dst)
PY

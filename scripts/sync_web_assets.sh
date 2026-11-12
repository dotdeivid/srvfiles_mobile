#!/usr/bin/env bash
# Regenera assets/www/ (frontend web servido por el modo servidor) a partir
# del repo srvfiles_web. Uso: scripts/sync_web_assets.sh [ruta/a/srvfiles_web]
set -euo pipefail

WEB_DIR="${1:-../srvfiles_web}"
APP_DIR="$(cd "$(dirname "$0")/.." && pwd)"

if [ ! -d "$WEB_DIR/frontend" ]; then
  echo "No se encontró $WEB_DIR/frontend" >&2
  exit 1
fi

(cd "$WEB_DIR/frontend" && npm ci && npm run build)
rm -rf "$APP_DIR/assets/www"
mkdir -p "$APP_DIR/assets/www"
cp -R "$WEB_DIR/frontend/dist/." "$APP_DIR/assets/www/"
touch "$APP_DIR/assets/www/assets/.gitkeep"
echo "assets/www actualizado desde $WEB_DIR ($(git -C "$WEB_DIR" rev-parse --short HEAD 2>/dev/null || echo 'sin git'))"

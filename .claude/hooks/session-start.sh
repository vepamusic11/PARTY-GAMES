#!/bin/bash
# Prepara una sesión de Claude Code en la web: instala Godot (misma versión
# que la CI) e importa el proyecto para que los tests corran de entrada.
# Idempotente: si Godot ya está en la versión correcta, no descarga nada.
set -euo pipefail

if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

GODOT_VERSION="4.4.1"
BIN_DIR="/usr/local/bin"
[ -w "$BIN_DIR" ] || { BIN_DIR="$HOME/.local/bin"; mkdir -p "$BIN_DIR"; }

if ! command -v godot >/dev/null 2>&1 || ! godot --version 2>/dev/null | grep -q "^${GODOT_VERSION}\.stable"; then
  tmp="$(mktemp -d)"
  curl -sSL --retry 4 -o "$tmp/godot.zip" \
    "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip"
  unzip -qo "$tmp/godot.zip" -d "$tmp"
  mv "$tmp/Godot_v${GODOT_VERSION}-stable_linux.x86_64" "$BIN_DIR/godot"
  chmod +x "$BIN_DIR/godot"
  rm -rf "$tmp"
fi

if [ -n "${CLAUDE_ENV_FILE:-}" ] && [ "$BIN_DIR" != "/usr/local/bin" ]; then
  echo "export PATH=\"$BIN_DIR:\$PATH\"" >> "$CLAUDE_ENV_FILE"
fi
export PATH="$BIN_DIR:$PATH"

# Genera el caché de clases (class_name) y los .import de fuentes e íconos.
cd "${CLAUDE_PROJECT_DIR:-$(pwd)}"
godot --headless --path . --import >/dev/null 2>&1 || true
godot --version

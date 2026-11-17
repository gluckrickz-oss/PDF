#!/usr/bin/env bash
set -euo pipefail
APP_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOTFS="$APP_DIR/runtime/rootfs"
LOADER="$ROOTFS/lib/x86_64-linux-gnu/ld-linux-x86-64.so.2"
[[ -x "$LOADER" ]] || LOADER="$ROOTFS/lib64/ld-linux-x86-64.so.2"
if [[ ! -x "$LOADER" ]]; then
  echo "Runtime Linux incompleto: loader glibc não encontrado." >&2
  exit 1
fi

LIBRARY_PATH="$(find "$ROOTFS/lib" "$ROOTFS/usr/lib" \( -type f -o -type l \) \( -name '*.so' -o -name '*.so.*' \) -printf '%h\n' 2>/dev/null | sort -u | paste -sd: -)"
export LD_LIBRARY_PATH="$LIBRARY_PATH${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export PATH="$APP_DIR/bin:$ROOTFS/usr/bin:$ROOTFS/bin:$PATH"
export PYTHONHOME="$ROOTFS/usr"
export PYTHONPATH="$APP_DIR/runtime/python-packages"
export PYTHONNOUSERSITE=1
export TESSDATA_PREFIX="$ROOTFS/usr/share/tesseract-ocr/5/tessdata"
export GS_LIB="$ROOTFS/usr/share/ghostscript/10.0.0/Resource/Init:$ROOTFS/usr/share/ghostscript/10.0.0/Resource/Font"
export GS_FONTPATH="$ROOTFS/usr/share/fonts/truetype/dejavu"
export UNO_PATH="$ROOTFS/usr/lib/libreoffice/program"
export URE_BOOTSTRAP="file://$ROOTFS/usr/lib/libreoffice/program/fundamentalrc"
export POPPLER_DATADIR="$ROOTFS/usr/share/poppler"
export HOME="${HOME:-$APP_DIR/data/home}"
export XDG_CONFIG_HOME="$APP_DIR/data/config"
export XDG_CACHE_HOME="$APP_DIR/data/cache"
export XDG_RUNTIME_DIR="$APP_DIR/data/run"
mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$XDG_RUNTIME_DIR" "$APP_DIR/data/uploads" "$APP_DIR/data/outputs"

exec "$LOADER" --library-path "$LIBRARY_PATH" "$ROOTFS/usr/bin/python3.11" "$APP_DIR/app.py" "$@"

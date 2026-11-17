#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
DIST="$REPO_ROOT/dist"
STAGE="$DIST/PDF2-Linux-Debian12-portable"
ROOTFS="$STAGE/runtime/rootfs"
POOL_STAGE="$DIST/deb-pool"

command -v dpkg-deb >/dev/null || { echo "dpkg-deb ausente no runner." >&2; exit 1; }
command -v python3 >/dev/null || { echo "Python 3 ausente no runner." >&2; exit 1; }

rm -rf "$STAGE" "$POOL_STAGE"
mkdir -p "$ROOTFS" "$POOL_STAGE" "$STAGE/runtime/python-packages" "$STAGE/bin" "$STAGE/data"
parts=("$REPO_ROOT"/vendor/apt/pool-bundle/pool.tar.part-*)
if [[ -f "${parts[0]}" ]]; then
  cat "${parts[@]}" | tar -xf - -C "$POOL_STAGE"
elif [[ -d "$REPO_ROOT/vendor/apt/pool" ]]; then
  cp -r "$REPO_ROOT/vendor/apt/pool" "$POOL_STAGE/"
else
  echo "Pacotes Debian offline não encontrados." >&2
  exit 1
fi
mapfile -t packages < <(find "$POOL_STAGE/pool" -type f -name '*.deb' | sort)
[[ ${#packages[@]} -gt 0 ]] || { echo "Nenhum pacote Debian encontrado no bundle." >&2; exit 1; }
for package in "${packages[@]}"; do
  dpkg-deb -x "$package" "$ROOTFS"
done

cp "$REPO_ROOT/app.py" "$REPO_ROOT/requirements.txt" "$STAGE/"
cp -r "$REPO_ROOT/static" "$REPO_ROOT/templates" "$STAGE/"
cp "$REPO_ROOT/linux/run-portable.sh" "$STAGE/run.sh"
cat > "$STAGE/LEIA-ME.txt" <<'EOF'
PDF2 Linux portátil — Debian 12 x64

Extraia o ZIP e execute ./run.sh. Não execute instaladores: Python e as ferramentas
Ghostscript, Poppler, Tesseract e LibreOffice estão dentro desta pasta.
O pacote e o runtime incluído foram preparados para Linux x86_64 com kernel compatível.
EOF
python3 -m pip install --disable-pip-version-check --no-warn-script-location --no-index \
  --find-links "$REPO_ROOT/vendor/wheels" --target "$STAGE/runtime/python-packages" \
  -r "$REPO_ROOT/requirements.txt"

for tool in gs pdftoppm pdftotext tesseract soffice; do
  target="$ROOTFS/usr/bin/$tool"
  if [[ ! -e "$target" ]]; then
    echo "Executável $tool não encontrado no rootfs empacotado." >&2
    exit 1
  fi
  cat > "$STAGE/bin/$tool" <<'WRAPPER'
#!/usr/bin/env bash
set -euo pipefail
APP_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
ROOTFS="$APP_DIR/runtime/rootfs"
LOADER="$ROOTFS/lib/x86_64-linux-gnu/ld-linux-x86-64.so.2"
[[ -x "$LOADER" ]] || LOADER="$ROOTFS/lib64/ld-linux-x86-64.so.2"
LIBRARY_PATH="$(find "$ROOTFS/lib" "$ROOTFS/usr/lib" \( -type f -o -type l \) \( -name '*.so' -o -name '*.so.*' \) -printf '%h\n' 2>/dev/null | sort -u | paste -sd: -)"
export LD_LIBRARY_PATH="$LIBRARY_PATH${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export TESSDATA_PREFIX="$ROOTFS/usr/share/tesseract-ocr/5/tessdata"
export GS_LIB="$ROOTFS/usr/share/ghostscript/10.0.0/Resource/Init:$ROOTFS/usr/share/ghostscript/10.0.0/Resource/Font"
export UNO_PATH="$ROOTFS/usr/lib/libreoffice/program"
export URE_BOOTSTRAP="file://$ROOTFS/usr/lib/libreoffice/program/fundamentalrc"
export POPPLER_DATADIR="$ROOTFS/usr/share/poppler"
if [[ "TOOL_NAME" == "soffice" ]]; then
  exec "$ROOTFS/usr/bin/soffice" "$@"
fi
exec "$LOADER" --library-path "$LIBRARY_PATH" "$ROOTFS/usr/bin/TOOL_NAME" "$@"
WRAPPER
  sed -i "s/TOOL_NAME/$tool/" "$STAGE/bin/$tool"
  chmod +x "$STAGE/bin/$tool"
done
chmod +x "$STAGE/run.sh"

export PDF2_BUNDLE_ROOT="$STAGE"
export PYTHONHOME="$ROOTFS/usr"
export PYTHONPATH="$STAGE/runtime/python-packages"
export PYTHONNOUSERSITE=1
export LD_LIBRARY_PATH="$(find "$ROOTFS/lib" "$ROOTFS/usr/lib" \( -type f -o -type l \) \( -name '*.so' -o -name '*.so.*' \) -printf '%h\n' 2>/dev/null | sort -u | paste -sd: -)"
LOADER="$ROOTFS/lib/x86_64-linux-gnu/ld-linux-x86-64.so.2"
[[ -x "$LOADER" ]] || LOADER="$ROOTFS/lib64/ld-linux-x86-64.so.2"
"$LOADER" --library-path "$LD_LIBRARY_PATH" "$ROOTFS/usr/bin/python3.11" -c 'import flask, PIL, pypdf, reportlab, cryptography'
"$STAGE/bin/gs" --version >/dev/null
"$STAGE/bin/pdftoppm" -v >/dev/null 2>&1
"$STAGE/bin/pdftotext" -v >/dev/null 2>&1
"$STAGE/bin/tesseract" --list-langs >/dev/null
"$STAGE/bin/soffice" --headless --version >/dev/null 2>&1

ZIP="$DIST/PDF2-Linux-Debian12-portable.zip"
rm -f "$ZIP"
cd "$DIST"
if command -v zip >/dev/null 2>&1; then
  zip -qr "$ZIP" "$(basename "$STAGE")"
else
  python3 - "$STAGE" "$ZIP" <<'PY'
import os
import stat
import sys
import zipfile
from pathlib import Path

root = Path(sys.argv[1])
archive = Path(sys.argv[2])
base = root.parent
with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=1, allowZip64=True) as zf:
    for current, dirs, files in os.walk(root, followlinks=False):
        current_path = Path(current)
        entries = [current_path / name for name in dirs + files]
        if current_path == root:
            entries.insert(0, root)
        for path in entries:
            rel = path.relative_to(base).as_posix()
            mode = path.lstat().st_mode
            info = zipfile.ZipInfo(rel + ("/" if stat.S_ISDIR(mode) else ""))
            info.create_system = 3
            info.external_attr = mode << 16
            if stat.S_ISLNK(mode):
                zf.writestr(info, os.readlink(path).encode())
            elif stat.S_ISDIR(mode):
                zf.writestr(info, b"")
            else:
                with path.open("rb") as src, zf.open(info, "w") as dst:
                    while chunk := src.read(1024 * 1024):
                        dst.write(chunk)
PY
fi
echo "Pacote pronto: $ZIP"

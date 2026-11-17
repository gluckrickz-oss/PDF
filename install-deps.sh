#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

ROOT="$(pwd)"
REPO="$ROOT/vendor/apt"
POOL_BUNDLE="$REPO/pool-bundle"
WHEELS="$ROOT/vendor/wheels"
PACKAGES=(
  ghostscript poppler-utils tesseract-ocr tesseract-ocr-eng tesseract-ocr-por
  fonts-dejavu-core python3-venv
)
if [ "${PDF2_FORCE_LIBREOFFICE:-0}" = "1" ] || ! command -v soffice >/dev/null 2>&1; then
  PACKAGES+=(
    libreoffice-core-nogui libreoffice-writer-nogui
    libreoffice-calc-nogui libreoffice-impress-nogui
  )
else
  echo "LibreOffice já encontrado; mantendo a instalação existente."
fi
DRY_RUN=0
[ "${1:-}" = "--dry-run" ] && DRY_RUN=1

die() { echo "ERRO: $*" >&2; exit 1; }
warn() { echo "AVISO: $*" >&2; }

if [ ! -d "$REPO/pool" ]; then
  parts=("$POOL_BUNDLE"/pool.tar.part-*)
  [ -f "${parts[0]}" ] || die "pool de pacotes e bundle offline ausentes em vendor/apt."
  mkdir -p "$REPO"
  cat "${parts[@]}" | tar -xf - -C "$REPO"
fi

[ -f "$REPO/Packages.gz" ] || die "repositório local ausente em vendor/apt."
[ -d "$WHEELS" ] || die "wheels Python ausentes em vendor/wheels."

if [ -r /etc/os-release ]; then
  . /etc/os-release
  if [ "${ID:-}" != "debian" ] || [ "${VERSION_ID:-}" != "12" ]; then
    if [ "${PDF2_IGNORE_OS:-0}" != "1" ]; then
      die "bundle criado para Debian 12 (bookworm) amd64; detectado ${PRETTY_NAME:-sistema desconhecido}. Gere um bundle para o destino ou use PDF2_IGNORE_OS=1 por sua conta e risco."
    fi
    warn "seguindo em ${PRETTY_NAME:-sistema desconhecido} por PDF2_IGNORE_OS=1."
  fi
fi
ARCH="$(dpkg --print-architecture 2>/dev/null || uname -m)"
[ "$ARCH" = "amd64" ] || die "bundle criado para amd64; arquitetura detectada: $ARCH."

if [ "$(id -u)" -eq 0 ]; then SUDO=(); else SUDO=(sudo); fi

mkdir -p "$REPO/lists/partial" "$REPO/cache/archives/partial"
printf 'deb [trusted=yes] file:%s ./\n' "$REPO" > "$REPO/sources.list"

APT_OPTS=(
  -o "Dir::Etc::sourcelist=$REPO/sources.list"
  -o "Dir::Etc::sourceparts=-"
  -o "Dir::State::Lists=$REPO/lists"
  -o "Dir::Cache=$REPO/cache"
  -o "APT::Get::List-Cleanup=0"
  -o "Acquire::Languages=none"
)
INSTALL_OPTS=("${APT_OPTS[@]}")
if [ "$DRY_RUN" -eq 1 ]; then
  INSTALL_OPTS+=("-o" "Dir::State::status=/dev/null" "-s")
fi

echo "Atualizando o repositório local (sem internet)..."
"${SUDO[@]}" apt-get "${APT_OPTS[@]}" update
echo "Instalando dependências do sistema a partir de vendor/apt..."
"${SUDO[@]}" apt-get "${INSTALL_OPTS[@]}" install -y --no-install-recommends "${PACKAGES[@]}"

if [ "$DRY_RUN" -eq 1 ]; then
  echo "Simulação concluída; nada foi instalado."
  exit 0
fi

if [ ! -x .venv/bin/python ] || ! .venv/bin/python -c 'import flask, pypdf' >/dev/null 2>&1; then
  echo "Criando ambiente virtual..."
  rm -rf .venv
  python3 -m venv .venv
fi
echo "Instalando dependências Python a partir de vendor/wheels..."
.venv/bin/pip install --no-index --find-links "$WHEELS" -r requirements.txt

missing=()
for bin in gs pdftoppm pdftotext tesseract soffice; do
  command -v "$bin" >/dev/null 2>&1 || missing+=("$bin")
done
if [ "${#missing[@]}" -gt 0 ]; then
  die "ainda faltam executáveis: ${missing[*]}"
fi
echo "Dependências prontas. Inicie com ./run.sh"

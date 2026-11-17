#!/usr/bin/env bash
# PDF2 - instalador para Linux
#
# Instala tudo o que o PDF2 precisa (Python, Ghostscript, Poppler, Tesseract,
# LibreOffice), baixa a versão mais recente do GitHub, prepara o ambiente
# Python e cria um atalho no menu de aplicativos.
#
# Uso:
#   bash setup-linux.sh             instala em ~/PDF2 e abre o programa
#   bash setup-linux.sh --sem-abrir só instala
#
# Variáveis opcionais:
#   PDF2_DIR=/outra/pasta   pasta de instalação (padrão: ~/PDF2)
#   PDF2_BRANCH=main        branch do GitHub
#   PDF2_PORT=8000          porta do servidor

set -euo pipefail

REPO_URL="https://github.com/gluckrickz-oss/PDF.git"
INSTALL_DIR="${PDF2_DIR:-$HOME/PDF2}"
BRANCH="${PDF2_BRANCH:-main}"
PORT="${PDF2_PORT:-8000}"
OPEN_AFTER=1
[ "${1:-}" = "--sem-abrir" ] && OPEN_AFTER=0

info() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33mAVISO: %s\033[0m\n' "$*" >&2; }
die()  { printf '\033[1;31mERRO: %s\033[0m\n' "$*" >&2; exit 1; }

if [ "$(id -u)" -eq 0 ]; then
  SUDO=()
else
  command -v sudo >/dev/null 2>&1 || die "o comando sudo não existe. Execute como root."
  SUDO=(sudo)
fi

# --------------------------------------------------------------------------
# 1. Pacotes do sistema
# --------------------------------------------------------------------------
install_apt() {
  export DEBIAN_FRONTEND=noninteractive
  "${SUDO[@]}" apt-get update
  "${SUDO[@]}" apt-get install -y --no-install-recommends \
    python3 python3-venv python3-pip git ca-certificates \
    ghostscript poppler-utils \
    tesseract-ocr tesseract-ocr-por tesseract-ocr-eng \
    fonts-dejavu-core
  # LibreOffice sem interface gráfica; se a distro não tiver os pacotes
  # "-nogui", usa os normais.
  if ! "${SUDO[@]}" apt-get install -y --no-install-recommends \
      libreoffice-writer-nogui libreoffice-calc-nogui libreoffice-impress-nogui; then
    "${SUDO[@]}" apt-get install -y --no-install-recommends \
      libreoffice-writer libreoffice-calc libreoffice-impress
  fi
}

install_dnf() {
  "${SUDO[@]}" dnf install -y \
    python3 python3-pip git ghostscript poppler-utils \
    tesseract tesseract-langpack-por \
    libreoffice-writer libreoffice-calc libreoffice-impress \
    dejavu-sans-fonts
}

install_zypper() {
  "${SUDO[@]}" zypper --non-interactive install \
    python3 python3-pip git ghostscript poppler-tools \
    tesseract-ocr tesseract-ocr-traineddata-portuguese tesseract-ocr-traineddata-english \
    libreoffice-writer libreoffice-calc libreoffice-impress \
    dejavu-fonts
}

install_pacman() {
  "${SUDO[@]}" pacman -Sy --needed --noconfirm \
    python python-pip git ghostscript poppler \
    tesseract tesseract-data-por tesseract-data-eng \
    libreoffice-fresh ttf-dejavu
}

info "Instalando Python, Ghostscript, Poppler, Tesseract e LibreOffice"
if command -v apt-get >/dev/null 2>&1; then
  install_apt
elif command -v dnf >/dev/null 2>&1; then
  install_dnf
elif command -v zypper >/dev/null 2>&1; then
  install_zypper
elif command -v pacman >/dev/null 2>&1; then
  install_pacman
else
  die "gerenciador de pacotes não reconhecido (suportados: apt, dnf, zypper, pacman)."
fi

missing=()
for bin in python3 git gs pdftoppm pdftotext tesseract soffice; do
  command -v "$bin" >/dev/null 2>&1 || missing+=("$bin")
done
[ "${#missing[@]}" -eq 0 ] || die "ainda faltam programas: ${missing[*]}"

python3 - <<'PY' || die "é preciso Python 3.10 ou mais recente."
import sys
sys.exit(0 if sys.version_info >= (3, 10) else 1)
PY

# --------------------------------------------------------------------------
# 2. Projeto do GitHub
# --------------------------------------------------------------------------
if [ -d "$INSTALL_DIR/.git" ]; then
  info "Atualizando o PDF2 em $INSTALL_DIR"
  git -C "$INSTALL_DIR" fetch --depth 1 origin "$BRANCH"
  git -C "$INSTALL_DIR" reset --hard "origin/$BRANCH"
else
  if [ -e "$INSTALL_DIR" ] && [ -n "$(ls -A "$INSTALL_DIR" 2>/dev/null)" ]; then
    die "$INSTALL_DIR já existe e não é uma cópia do GitHub. Use PDF2_DIR=/outra/pasta."
  fi
  info "Baixando o PDF2 do GitHub para $INSTALL_DIR"
  git clone --depth 1 --branch "$BRANCH" "$REPO_URL" "$INSTALL_DIR"
fi

# --------------------------------------------------------------------------
# 3. Ambiente Python
# --------------------------------------------------------------------------
info "Preparando o ambiente Python"
VENV="$INSTALL_DIR/.venv"
if [ ! -x "$VENV/bin/python" ]; then
  python3 -m venv "$VENV"
fi
"$VENV/bin/python" -m pip install --disable-pip-version-check --upgrade pip
"$VENV/bin/python" -m pip install --disable-pip-version-check -r "$INSTALL_DIR/requirements.txt"
"$VENV/bin/python" -c "import flask, pypdf, PIL, reportlab, cryptography" \
  || die "as bibliotecas Python não carregaram."

# --------------------------------------------------------------------------
# 4. Atalho para abrir o programa
# --------------------------------------------------------------------------
LAUNCHER="$INSTALL_DIR/iniciar-pdf2.sh"
cat > "$LAUNCHER" <<EOF
#!/usr/bin/env bash
cd "$INSTALL_DIR"
( sleep 2; xdg-open "http://127.0.0.1:$PORT/" >/dev/null 2>&1 || true ) &
exec "$VENV/bin/python" app.py --port $PORT "\$@"
EOF
chmod +x "$LAUNCHER"

APPS_DIR="$HOME/.local/share/applications"
mkdir -p "$APPS_DIR"
cat > "$APPS_DIR/pdf2.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=PDF2
Comment=Ferramentas de PDF
Exec=$LAUNCHER
Terminal=true
Icon=application-pdf
Categories=Office;
EOF

info "Pronto!"
echo "Para abrir: $LAUNCHER  (ou procure \"PDF2\" no menu de aplicativos)"
echo "Endereço: http://127.0.0.1:$PORT/"

if [ "$OPEN_AFTER" -eq 1 ]; then
  exec "$LAUNCHER"
fi

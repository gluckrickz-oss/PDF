#!/usr/bin/env bash
# PDF2 - instalador e atualizador para Linux
#
# Primeira vez: instala tudo o que o PDF2 precisa (Python, Ghostscript,
# Poppler, Tesseract, LibreOffice), baixa o projeto do GitHub, prepara o
# ambiente Python, cria o serviço "pdf2" e o comando "pdf2".
# Já instalado: atualiza o projeto e as bibliotecas e reinicia o serviço.
#
# Uso:
#   bash setup-linux.sh               instala ou atualiza e abre o programa
#   bash setup-linux.sh --sem-abrir   instala ou atualiza sem abrir o navegador
#   bash setup-linux.sh --completo    reinstala também os pacotes do sistema
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
FULL=0
for arg in "$@"; do
  case "$arg" in
    --sem-abrir) OPEN_AFTER=0 ;;
    --completo)  FULL=1 ;;
    *) printf 'Opção desconhecida: %s\n' "$arg" >&2; exit 1 ;;
  esac
done

SERVICE="pdf2"
UNIT="/etc/systemd/system/$SERVICE.service"
CONFIG="/etc/default/$SERVICE"
COMMAND="/usr/local/bin/pdf2"
RUN_USER="$(id -un)"

info() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33mAVISO: %s\033[0m\n' "$*" >&2; }
die()  { printf '\033[1;31mERRO: %s\033[0m\n' "$*" >&2; exit 1; }

if [ "$(id -u)" -eq 0 ]; then
  SUDO=()
else
  command -v sudo >/dev/null 2>&1 || die "o comando sudo não existe. Execute como root."
  SUDO=(sudo)
fi

if [ -d "$INSTALL_DIR/.git" ] && [ -x "$INSTALL_DIR/.venv/bin/python" ]; then
  MODE="atualizar"
else
  MODE="instalar"
fi

# --------------------------------------------------------------------------
# 1. Pacotes do sistema
# --------------------------------------------------------------------------
REQUIRED_BINS=(python3 git curl gs pdftoppm pdftotext tesseract soffice)

all_bins_present() {
  local bin
  for bin in "${REQUIRED_BINS[@]}"; do
    command -v "$bin" >/dev/null 2>&1 || return 1
  done
  python3 -c 'import venv, ensurepip' >/dev/null 2>&1
}

install_apt() {
  export DEBIAN_FRONTEND=noninteractive
  "${SUDO[@]}" apt-get update
  "${SUDO[@]}" apt-get install -y --no-install-recommends \
    python3 python3-venv python3-pip git curl ca-certificates \
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
    python3 python3-pip git curl ghostscript poppler-utils \
    tesseract tesseract-langpack-por \
    libreoffice-writer libreoffice-calc libreoffice-impress \
    dejavu-sans-fonts
}

install_zypper() {
  "${SUDO[@]}" zypper --non-interactive install \
    python3 python3-pip git curl ghostscript poppler-tools \
    tesseract-ocr tesseract-ocr-traineddata-portuguese tesseract-ocr-traineddata-english \
    libreoffice-writer libreoffice-calc libreoffice-impress \
    dejavu-fonts
}

install_pacman() {
  "${SUDO[@]}" pacman -Sy --needed --noconfirm \
    python python-pip git curl ghostscript poppler \
    tesseract tesseract-data-por tesseract-data-eng \
    libreoffice-fresh ttf-dejavu
}

if [ "$MODE" = "atualizar" ] && [ "$FULL" -eq 0 ] && all_bins_present; then
  info "Programas do sistema já instalados (use --completo para reinstalar)"
else
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
fi

missing=()
for bin in "${REQUIRED_BINS[@]}"; do
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
  OLD_REV="$(git -C "$INSTALL_DIR" rev-parse --short HEAD 2>/dev/null || echo '?')"
  git -C "$INSTALL_DIR" fetch --depth 1 origin "$BRANCH"
  git -C "$INSTALL_DIR" reset --hard "origin/$BRANCH"
  NEW_REV="$(git -C "$INSTALL_DIR" rev-parse --short HEAD)"
  if [ "$OLD_REV" = "$NEW_REV" ]; then
    echo "Já estava na versão mais recente ($NEW_REV)."
  else
    echo "Atualizado: $OLD_REV -> $NEW_REV"
  fi
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
"$VENV/bin/python" -m pip install --disable-pip-version-check --quiet --upgrade pip
"$VENV/bin/python" -m pip install --disable-pip-version-check --quiet -r "$INSTALL_DIR/requirements.txt"
"$VENV/bin/python" -c "import flask, pypdf, PIL, reportlab, cryptography" \
  || die "as bibliotecas Python não carregaram."

# --------------------------------------------------------------------------
# 4. Comando "pdf2" (status, start, stop...)
# --------------------------------------------------------------------------
info "Criando o comando pdf2"
"${SUDO[@]}" tee "$COMMAND" >/dev/null <<EOF
#!/usr/bin/env bash
# Comando de controle do PDF2 (gerado pelo setup-linux.sh)
INSTALL_DIR="$INSTALL_DIR"
SERVICE="$SERVICE"
CONFIG="$CONFIG"
EOF
"${SUDO[@]}" tee -a "$COMMAND" >/dev/null <<'EOF'
PDF2_HOST=127.0.0.1
PDF2_PORT=8000
[ -r "$CONFIG" ] && . "$CONFIG"

if [ "$(id -u)" -eq 0 ]; then SUDO=(); else SUDO=(sudo); fi
HAS_SYSTEMD=0
if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then HAS_SYSTEMD=1; fi
PIDFILE="$INSTALL_DIR/data/pdf2.pid"
LOGFILE="$INSTALL_DIR/data/pdf2.log"
URL="http://127.0.0.1:$PDF2_PORT/"

responde() { curl -fsS -o /dev/null --max-time 3 "$URL" 2>/dev/null; }

esperar() {
  local i
  for i in $(seq 1 20); do responde && return 0; sleep 1; done
  return 1
}

enderecos() {
  echo "Endereço nesta máquina: $URL"
  if [ "$PDF2_HOST" = "0.0.0.0" ]; then
    local ip
    for ip in $(hostname -I 2>/dev/null); do
      case "$ip" in *:*|127.*) ;; *) echo "Endereço na rede:       http://$ip:$PDF2_PORT/" ;; esac
    done
  else
    echo "Acesso pela rede: desativado (ative com: pdf2 rede)"
  fi
}

rodando_sem_systemd() { [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; }

iniciar() {
  if [ "$HAS_SYSTEMD" -eq 1 ]; then
    "${SUDO[@]}" systemctl start "$SERVICE"
  elif ! rodando_sem_systemd; then
    mkdir -p "$INSTALL_DIR/data"
    cd "$INSTALL_DIR" || exit 1
    nohup "$INSTALL_DIR/.venv/bin/python" app.py --host "$PDF2_HOST" --port "$PDF2_PORT" \
      >>"$LOGFILE" 2>&1 &
    echo $! >"$PIDFILE"
  fi
  if esperar; then echo "PDF2 iniciado."; enderecos; else echo "O PDF2 não respondeu. Veja: pdf2 logs"; return 1; fi
}

parar() {
  if [ "$HAS_SYSTEMD" -eq 1 ]; then
    "${SUDO[@]}" systemctl stop "$SERVICE"
  elif rodando_sem_systemd; then
    kill "$(cat "$PIDFILE")" 2>/dev/null; rm -f "$PIDFILE"
  fi
  echo "PDF2 parado."
}

case "${1:-}" in
  start|iniciar)   iniciar ;;
  stop|parar)      parar ;;
  restart|reiniciar)
    if [ "$HAS_SYSTEMD" -eq 1 ]; then "${SUDO[@]}" systemctl restart "$SERVICE"; else parar; fi
    iniciar ;;
  status)
    if responde; then echo "PDF2: RODANDO"; else echo "PDF2: PARADO"; fi
    enderecos
    if [ "$HAS_SYSTEMD" -eq 1 ]; then
      echo "Inicia com o computador: $(systemctl is-enabled "$SERVICE" 2>/dev/null || echo nao)"
      echo
      systemctl --no-pager --lines=5 status "$SERVICE" 2>/dev/null || true
    fi ;;
  logs)
    if [ "$HAS_SYSTEMD" -eq 1 ]; then journalctl -u "$SERVICE" -n 50 --no-pager; else tail -n 50 "$LOGFILE"; fi ;;
  abrir|open)
    responde || iniciar || exit 1
    xdg-open "$URL" >/dev/null 2>&1 || echo "Abra no navegador: $URL" ;;
  atualizar|update)
    curl -fsSL https://raw.githubusercontent.com/gluckrickz-oss/PDF/main/setup-linux.sh -o /tmp/pdf2-setup.sh \
      && PDF2_DIR="$INSTALL_DIR" PDF2_PORT="$PDF2_PORT" bash /tmp/pdf2-setup.sh --sem-abrir ;;
  rede)
    bash "$INSTALL_DIR/habilitar-rede.sh" "${@:2}" ;;
  *)
    cat <<USO
Uso: pdf2 COMANDO

  pdf2 status      mostra se está rodando e os endereços
  pdf2 start       inicia
  pdf2 stop        para
  pdf2 restart     reinicia
  pdf2 abrir       inicia (se preciso) e abre no navegador
  pdf2 logs        últimas mensagens do servidor
  pdf2 atualizar   baixa a versão mais recente do GitHub
  pdf2 rede        libera o acesso pela rede (pdf2 rede --desativar volta ao local)
USO
    [ -z "${1:-}" ] || exit 1 ;;
esac
EOF
"${SUDO[@]}" chmod 755 "$COMMAND"

# --------------------------------------------------------------------------
# 5. Serviço do sistema (inicia com o computador)
# --------------------------------------------------------------------------
HAS_SYSTEMD=0
if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then HAS_SYSTEMD=1; fi

# Configuração: preserva o modo (local/rede) já escolhido.
if [ ! -f "$CONFIG" ]; then
  HOST=127.0.0.1
  # Instalações antigas do habilitar-rede.sh gravavam o host direto no serviço.
  if [ -f "$UNIT" ] && grep -q -- "--host 0.0.0.0" "$UNIT"; then HOST=0.0.0.0; fi
  printf 'PDF2_HOST=%s\nPDF2_PORT=%s\n' "$HOST" "$PORT" | "${SUDO[@]}" tee "$CONFIG" >/dev/null
fi
# shellcheck disable=SC1090
PORT="$(PDF2_PORT="$PORT"; . "$CONFIG"; echo "$PDF2_PORT")"

if [ "$HAS_SYSTEMD" -eq 1 ]; then
  info "Configurando o serviço $SERVICE"
  "${SUDO[@]}" tee "$UNIT" >/dev/null <<EOF
[Unit]
Description=PDF2 - ferramentas de PDF
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$RUN_USER
WorkingDirectory=$INSTALL_DIR
Environment=HOME=$HOME
Environment=PYTHONUNBUFFERED=1
Environment=PDF2_HOST=127.0.0.1
Environment=PDF2_PORT=8000
EnvironmentFile=-$CONFIG
ExecStart=$INSTALL_DIR/.venv/bin/python $INSTALL_DIR/app.py --host \${PDF2_HOST} --port \${PDF2_PORT}
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  "${SUDO[@]}" systemctl daemon-reload
  "${SUDO[@]}" systemctl enable "$SERVICE" >/dev/null 2>&1
  # Libera a porta caso o PDF2 antigo tenha sido aberto pelo atalho.
  pkill -u "$RUN_USER" -f "$INSTALL_DIR/app.py" 2>/dev/null || true
  pkill -u "$RUN_USER" -f "^$VENV/bin/python app.py" 2>/dev/null || true
  "${SUDO[@]}" systemctl restart "$SERVICE"
else
  warn "systemd não encontrado: o PDF2 não iniciará sozinho com o computador. Use: pdf2 start"
  "$COMMAND" stop >/dev/null 2>&1 || true
fi

# --------------------------------------------------------------------------
# 6. Atalho no menu
# --------------------------------------------------------------------------
LAUNCHER="$INSTALL_DIR/iniciar-pdf2.sh"
cat > "$LAUNCHER" <<EOF
#!/usr/bin/env bash
exec $COMMAND abrir
EOF
chmod +x "$LAUNCHER"

APPS_DIR="$HOME/.local/share/applications"
mkdir -p "$APPS_DIR"
cat > "$APPS_DIR/pdf2.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=PDF2
Comment=Ferramentas de PDF
Exec=$COMMAND abrir
Terminal=false
Icon=application-pdf
Categories=Office;
EOF

if [ "$HAS_SYSTEMD" -eq 0 ]; then
  "$COMMAND" start >/dev/null || true
fi

# Espera o servidor responder antes de mostrar o resultado.
for _ in $(seq 1 20); do
  curl -fsS -o /dev/null --max-time 3 "http://127.0.0.1:$PORT/" 2>/dev/null && break
  sleep 1
done

if [ "$MODE" = "instalar" ]; then info "Instalação concluída!"; else info "Atualização concluída!"; fi
STATUS="$("$COMMAND" status 2>/dev/null || true)"
printf '%s\n' "$STATUS" | sed -n '1,4p'
cat <<EOF

Comandos:
  pdf2 status      mostra se está rodando e os endereços
  pdf2 start       inicia
  pdf2 stop        para
  pdf2 restart     reinicia
  pdf2 abrir       abre no navegador
  pdf2 logs        últimas mensagens do servidor
  pdf2 atualizar   baixa a versão mais recente do GitHub
  pdf2 rede        libera o acesso pela rede
EOF

if [ "$OPEN_AFTER" -eq 1 ]; then
  "$COMMAND" abrir || true
fi

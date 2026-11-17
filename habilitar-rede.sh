#!/usr/bin/env bash
# PDF2 - habilita o acesso pela rede (Linux)
#
# Deixa o PDF2 rodando como serviço do sistema, acessível de outros
# computadores da rede em http://IP-DESTA-MAQUINA:8000. O serviço inicia
# junto com o computador e reinicia sozinho se cair.
#
# Rode depois do setup-linux.sh.
#
# Uso:
#   bash habilitar-rede.sh              habilita
#   bash habilitar-rede.sh --desativar  volta a funcionar só nesta máquina
#   bash habilitar-rede.sh --status     mostra se o serviço está rodando
#
# Variáveis opcionais:
#   PDF2_DIR=/outra/pasta   pasta onde o PDF2 foi instalado (padrão: ~/PDF2)
#   PDF2_PORT=8000          porta usada na rede

set -euo pipefail

INSTALL_DIR="${PDF2_DIR:-$HOME/PDF2}"
PORT="${PDF2_PORT:-8000}"
SERVICE="pdf2"
UNIT="/etc/systemd/system/$SERVICE.service"
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
command -v systemctl >/dev/null 2>&1 || die "este sistema não usa systemd; não é possível criar o serviço."

firewall() {
  # $1 = abrir | fechar
  if command -v ufw >/dev/null 2>&1 && "${SUDO[@]}" ufw status 2>/dev/null | grep -q "Status: active"; then
    if [ "$1" = abrir ]; then
      "${SUDO[@]}" ufw allow "$PORT/tcp" comment "PDF2" >/dev/null
    else
      "${SUDO[@]}" ufw delete allow "$PORT/tcp" >/dev/null 2>&1 || true
    fi
    echo "Firewall (ufw): porta $PORT atualizada."
  elif command -v firewall-cmd >/dev/null 2>&1 && "${SUDO[@]}" firewall-cmd --state >/dev/null 2>&1; then
    if [ "$1" = abrir ]; then
      "${SUDO[@]}" firewall-cmd --permanent --add-port="$PORT/tcp" >/dev/null
    else
      "${SUDO[@]}" firewall-cmd --permanent --remove-port="$PORT/tcp" >/dev/null 2>&1 || true
    fi
    "${SUDO[@]}" firewall-cmd --reload >/dev/null
    echo "Firewall (firewalld): porta $PORT atualizada."
  else
    echo "Nenhum firewall ativo encontrado (ufw/firewalld); nada a ajustar."
  fi
}

lan_addresses() {
  hostname -I 2>/dev/null | tr ' ' '\n' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | grep -v '^127\.' || true
}

case "${1:-}" in
  --status)
    systemctl --no-pager status "$SERVICE" || true
    exit 0
    ;;
  --desativar)
    info "Desativando o acesso pela rede"
    "${SUDO[@]}" systemctl disable --now "$SERVICE" 2>/dev/null || true
    "${SUDO[@]}" rm -f "$UNIT"
    "${SUDO[@]}" systemctl daemon-reload
    firewall fechar
    echo "Pronto. Para usar só nesta máquina, abra o atalho PDF2 normalmente."
    exit 0
    ;;
  "") ;;
  *) die "opção desconhecida: $1 (use --desativar ou --status)" ;;
esac

[ -f "$INSTALL_DIR/app.py" ] || die "PDF2 não encontrado em $INSTALL_DIR. Rode antes o setup-linux.sh (ou use PDF2_DIR=/pasta)."
[ -x "$INSTALL_DIR/.venv/bin/python" ] || die "ambiente Python não encontrado em $INSTALL_DIR/.venv. Rode antes o setup-linux.sh."

if command -v ss >/dev/null 2>&1 && ss -ltn "sport = :$PORT" | grep -q LISTEN; then
  if ! systemctl is-active --quiet "$SERVICE"; then
    die "a porta $PORT já está em uso. Feche o PDF2 aberto pelo atalho (ou use PDF2_PORT=outra)."
  fi
fi

info "Criando o serviço $SERVICE (inicia junto com o computador)"
"${SUDO[@]}" tee "$UNIT" >/dev/null <<EOF
[Unit]
Description=PDF2 - ferramentas de PDF na rede
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$RUN_USER
WorkingDirectory=$INSTALL_DIR
Environment=HOME=$HOME
Environment=PYTHONUNBUFFERED=1
ExecStart=$INSTALL_DIR/.venv/bin/python $INSTALL_DIR/app.py --host 0.0.0.0 --port $PORT
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
"${SUDO[@]}" systemctl daemon-reload
"${SUDO[@]}" systemctl enable "$SERVICE" >/dev/null 2>&1
"${SUDO[@]}" systemctl restart "$SERVICE"

info "Liberando a porta $PORT no firewall"
firewall abrir

info "Verificando"
ok=0
for _ in $(seq 1 15); do
  if curl -fsS -o /dev/null "http://127.0.0.1:$PORT/" 2>/dev/null; then ok=1; break; fi
  sleep 1
done
if [ "$ok" -ne 1 ]; then
  "${SUDO[@]}" journalctl -u "$SERVICE" -n 20 --no-pager || true
  die "o serviço não respondeu. Veja as mensagens acima."
fi

info "Pronto! O PDF2 está disponível na rede"
addrs="$(lan_addresses)"
if [ -n "$addrs" ]; then
  echo "Nos outros computadores, abra no navegador:"
  for ip in $addrs; do echo "   http://$ip:$PORT/"; done
else
  echo "Abra http://IP-DESTA-MAQUINA:$PORT/ nos outros computadores."
fi
echo
echo "Atenção: qualquer pessoa da rede consegue usar o PDF2 (não há senha)."
echo "Para desativar: bash habilitar-rede.sh --desativar"

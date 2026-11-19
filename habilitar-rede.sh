#!/usr/bin/env bash
# PDF2 - liga ou desliga o acesso pela rede (Linux)
#
# Faz o serviço do PDF2 aceitar conexões de outros computadores da rede
# (http://IP-DESTA-MAQUINA:8000) e libera a porta no firewall.
# Rode depois do setup-linux.sh. Também disponível como "pdf2 rede".
#
# Uso:
#   bash habilitar-rede.sh              libera o acesso pela rede
#   bash habilitar-rede.sh --desativar  volta a funcionar só nesta máquina
#   bash habilitar-rede.sh --status     mostra o estado atual

set -euo pipefail

CONFIG="/etc/default/pdf2"
COMMAND="/usr/local/bin/pdf2"

info() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31mERRO: %s\033[0m\n' "$*" >&2; exit 1; }

if [ "$(id -u)" -eq 0 ]; then SUDO=(); else SUDO=(sudo); fi

[ -x "$COMMAND" ] && [ -f "$CONFIG" ] || die "PDF2 não instalado. Rode antes o setup-linux.sh."

PDF2_PORT=8000
# shellcheck disable=SC1090
. "$CONFIG"
PORT="$PDF2_PORT"

set_host() {
  if grep -q '^PDF2_HOST=' "$CONFIG"; then
    "${SUDO[@]}" sed -i "s/^PDF2_HOST=.*/PDF2_HOST=$1/" "$CONFIG"
  else
    echo "PDF2_HOST=$1" | "${SUDO[@]}" tee -a "$CONFIG" >/dev/null
  fi
}

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

case "${1:-}" in
  --status)
    "$COMMAND" status
    ;;
  --desativar)
    info "Desativando o acesso pela rede"
    set_host 127.0.0.1
    firewall fechar
    "$COMMAND" restart
    ;;
  "")
    info "Liberando o acesso pela rede"
    set_host 0.0.0.0
    firewall abrir
    "$COMMAND" restart
    echo
    echo "Atenção: qualquer pessoa da rede consegue usar o PDF2 (não há senha)."
    echo "Para desativar: pdf2 rede --desativar"
    ;;
  *)
    die "opção desconhecida: $1 (use --desativar ou --status)"
    ;;
esac

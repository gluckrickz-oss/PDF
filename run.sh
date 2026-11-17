#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

if [ ! -x .venv/bin/python ] || ! .venv/bin/python -c 'import flask, pypdf' >/dev/null 2>&1; then
  echo "Criando ambiente virtual..."
  rm -rf .venv
  python3 -m venv .venv
  .venv/bin/pip install --upgrade pip
  if ls vendor/wheels/*.whl >/dev/null 2>&1; then
    .venv/bin/pip install --no-index --find-links vendor/wheels -r requirements.txt
  else
    .venv/bin/pip install -r requirements.txt
  fi
fi

missing=()
for bin in gs pdftoppm pdftotext tesseract soffice; do
  command -v "$bin" >/dev/null 2>&1 || missing+=("$bin")
done
if [ "${#missing[@]}" -gt 0 ]; then
  echo "AVISO: dependências do sistema ausentes: ${missing[*]}" >&2
  echo "Execute ./install-deps.sh para instalá-las a partir de vendor/apt." >&2
fi

exec .venv/bin/python app.py "$@"

# PDF

## Baixar versão pronta

- [**Windows x64 — baixar ZIP**](https://github.com/gluckrickz-oss/PDF/actions/runs/44124720998/artifacts/14345534944) — extraia e execute `run-windows.bat`.
- [**Linux Debian 12 x64 — baixar ZIP**](https://github.com/gluckrickz-oss/PDF/actions/runs/44124720998/artifacts/14347077299) — extraia e execute `run.sh`.

Os dois pacotes incluem Python e as ferramentas necessárias. É só extrair e usar; não instale dependências. Os links do GitHub Actions ficam disponíveis por 90 dias. [Ver builds e downloads mais recentes](https://github.com/gluckrickz-oss/PDF/actions/workflows/build-windows-portable.yml).

Aplicação local para trabalhar com arquivos PDF pelo navegador. O servidor usa Flask e reúne ferramentas para manipular PDFs e converter documentos e imagens.

## Requisitos

O bundle offline incluído foi preparado para Debian 12 (bookworm), amd64 e Python 3.11. Ele contém os pacotes do sistema e wheels Python usados na instalação. Para manter os arquivos compatíveis com o GitHub, os pacotes APT estão divididos em partes e são reconstruídos automaticamente na primeira execução do instalador.

## Instalação e execução

```bash
./install-deps.sh
./run.sh
```

Abra no navegador o endereço local exibido pelo servidor. Para iniciar sem o bundle offline, instale os pacotes listados em `requirements.txt` e as ferramentas de sistema usadas pelo app (Ghostscript, Poppler, Tesseract e LibreOffice).

O script `install-deps.sh` instala dependências a partir de `vendor/apt` e requer Debian 12 amd64. `run.sh` cria o ambiente virtual em `.venv` e usa `vendor/wheels` quando disponível.

O pacote Windows contém Ghostscript sob a distribuição AGPL; consulte `THIRD-PARTY-NOTICES.txt` antes de redistribuí-lo.

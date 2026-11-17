# PDF

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

## Downloads compactados, sem instalador

Os ZIPs prontos são publicados como artefatos na página [Actions](https://github.com/gluckrickz-oss/PDF/actions/workflows/build-windows-portable.yml). Abra a execução mais recente e baixe os artefatos pelo nome:

- **Windows x64:** `PDF2-Windows-portable` — extraia e execute `run-windows.bat`. Python, Ghostscript, Poppler, Tesseract (inglês e português) e LibreOffice estão dentro da pasta.
- **Linux Debian 12 x64:** `PDF2-Linux-Debian12-portable` — extraia e execute `run.sh`. Python, Ghostscript, Poppler, Tesseract e LibreOffice estão dentro da pasta.

Os dois pacotes executam sem instalador e sem instalar dependências no computador. O pacote Windows contém Ghostscript sob a distribuição AGPL; consulte `THIRD-PARTY-NOTICES.txt` antes de redistribuí-lo.

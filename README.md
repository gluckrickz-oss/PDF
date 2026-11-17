# PDF

## Baixar

### Windows

[**Baixar PDF2-Windows-portable.zip**](https://github.com/gluckrickz-oss/PDF/releases/latest/download/PDF2-Windows-portable.zip): extraia e dê dois cliques em `iniciar.bat`.

O pacote já traz Python, Ghostscript, Poppler, Tesseract (português e inglês) e LibreOffice. Não é preciso instalar nada.

### Linux

```bash
curl -fsSL https://raw.githubusercontent.com/gluckrickz-oss/PDF/main/setup-linux.sh -o setup-linux.sh && bash setup-linux.sh
```

O `setup-linux.sh` instala Python, Ghostscript, Poppler, Tesseract e LibreOffice pelo gerenciador de pacotes (apt, dnf, zypper ou pacman), baixa o projeto em `~/PDF2`, prepara o ambiente Python e cria o atalho "PDF2" no menu.

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

O pacote Windows contém Ghostscript, distribuído sob a AGPL.

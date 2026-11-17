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

## Windows portátil

O workflow **Build PDF2 Windows portable** gera o artefato `PDF2-Windows-portable` na aba **Actions**. Baixe e extraia `PDF2-Windows-portable.zip` em uma pasta e execute `run-windows.bat`. O pacote inclui o runtime Python e as dependências Ghostscript, Poppler, Tesseract (inglês e português) e LibreOffice; ele não altera o PATH do Windows nem exige uma instalação manual dessas ferramentas. A versão é para Windows x64.

O bundle de Ghostscript usa a distribuição AGPL. Consulte `THIRD-PARTY-NOTICES.txt` dentro do pacote antes de redistribuí-lo.

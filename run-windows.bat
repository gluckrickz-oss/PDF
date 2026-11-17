@echo off
setlocal
cd /d "%~dp0"

set "APPROOT=%~dp0"
set "TOOLS=%APPROOT%vendor\windows"
set "PYTHONHOME=%APPROOT%runtime"
set "PATH=%TOOLS%\ghostscript\bin;%TOOLS%\poppler\bin;%TOOLS%\tesseract;%TOOLS%\libreoffice\program;%APPROOT%runtime;%PATH%"
set "TESSDATA_PREFIX=%TOOLS%\tesseract"
set "UNO_PATH=%TOOLS%\libreoffice\program"

if not exist "%APPROOT%runtime\python.exe" (
  echo Pacote portatil incompleto: runtime\python.exe nao encontrado.
  pause
  exit /b 1
)
if not exist "%TOOLS%\ghostscript\bin\gswin64c.exe" (
  echo Pacote portatil incompleto: Ghostscript nao encontrado.
  pause
  exit /b 1
)
if not exist "%TOOLS%\poppler\bin\pdftoppm.exe" (
  echo Pacote portatil incompleto: Poppler nao encontrado.
  pause
  exit /b 1
)
if not exist "%TOOLS%\tesseract\tesseract.exe" (
  echo Pacote portatil incompleto: Tesseract nao encontrado.
  pause
  exit /b 1
)
if not exist "%TOOLS%\libreoffice\program\soffice.exe" (
  echo Pacote portatil incompleto: LibreOffice nao encontrado.
  pause
  exit /b 1
)

start "" powershell -NoProfile -WindowStyle Hidden -Command "Start-Sleep -Seconds 2; Start-Process 'http://127.0.0.1:8000/'"
"%APPROOT%runtime\python.exe" "%APPROOT%app.py"
set "APP_EXIT=%ERRORLEVEL%"
if not "%APP_EXIT%"=="0" pause
exit /b %APP_EXIT%

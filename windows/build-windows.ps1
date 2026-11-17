$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent $PSScriptRoot
$DistRoot = Join-Path $RepoRoot 'dist'
$Stage = Join-Path $DistRoot 'PDF2-Windows-portable'
$Downloads = Join-Path $DistRoot '_windows-downloads'
$Tools = Join-Path $Stage 'vendor\windows'

$GhostscriptVersion = '10.7.1'
$TesseractVersion = '5.5.3.20260724'
$LibreOfficeVersion = '26.2.3'
$PopplerVersion = '26.09.0-0'
$PopplerSha256 = '7a6f256a0ddf7536182246a5733331bf4677cbcc34f4663774947ad34556c8d0'
$TessdataCommit = '87416418657359cb625c412a48b6e1d6d41c29bd'

function Copy-RequiredDirectory([string]$Source, [string]$Destination) {
    if (-not (Test-Path -LiteralPath $Source -PathType Container)) {
        throw "Diretorio necessario nao encontrado: $Source"
    }
    New-Item -ItemType Directory -Force -Path $Destination | Out-Null
    Copy-Item -Path (Join-Path $Source '*') -Destination $Destination -Recurse -Force
}

if (-not $IsWindows) {
    throw 'Este empacotador precisa rodar em Windows x64.'
}
if (-not $env:pythonLocation -or -not (Test-Path (Join-Path $env:pythonLocation 'python.exe'))) {
    throw 'Python x64 nao foi preparado pelo workflow.'
}
if (-not (Get-Command choco.exe -ErrorAction SilentlyContinue)) {
    throw 'Chocolatey nao esta disponivel no runner de build.'
}

Remove-Item -LiteralPath $Stage, $Downloads -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $Stage, $Downloads, $Tools | Out-Null

Copy-Item (Join-Path $RepoRoot 'app.py') $Stage
Copy-Item (Join-Path $RepoRoot 'requirements.txt') $Stage
Copy-Item (Join-Path $RepoRoot 'run-windows.bat') $Stage
Copy-RequiredDirectory (Join-Path $RepoRoot 'static') (Join-Path $Stage 'static')
Copy-RequiredDirectory (Join-Path $RepoRoot 'templates') (Join-Path $Stage 'templates')
if (Test-Path (Join-Path $RepoRoot 'README.md')) {
    Copy-Item (Join-Path $RepoRoot 'README.md') $Stage
}

$ChocolateyPackages = @(
    @{ Name = 'ghostscript'; Version = $GhostscriptVersion },
    @{ Name = 'tesseract'; Version = $TesseractVersion },
    @{ Name = 'libreoffice-fresh'; Version = $LibreOfficeVersion }
)
foreach ($Package in $ChocolateyPackages) {
    & choco.exe install $Package.Name "--version=$($Package.Version)" --yes --no-progress --force
    if ($LASTEXITCODE -notin @(0, 3010)) {
        throw "Falha ao preparar $($Package.Name) $($Package.Version) (codigo $LASTEXITCODE)."
    }
}

$GsRoot = Join-Path $env:ProgramFiles 'gs'
$GsInstall = Get-ChildItem -LiteralPath $GsRoot -Directory -ErrorAction Stop |
    Where-Object { Test-Path (Join-Path $_.FullName 'bin\gswin64c.exe') } |
    Sort-Object Name -Descending |
    Select-Object -First 1
if (-not $GsInstall) {
    throw 'Ghostscript x64 nao foi localizado apos a preparacao.'
}
Copy-RequiredDirectory $GsInstall.FullName (Join-Path $Tools 'ghostscript')

$TesseractSource = Join-Path $env:ProgramFiles 'Tesseract-OCR'
Copy-RequiredDirectory $TesseractSource (Join-Path $Tools 'tesseract')
$Tessdata = Join-Path $Tools 'tesseract\tessdata'
New-Item -ItemType Directory -Force -Path $Tessdata | Out-Null
foreach ($Language in @('eng', 'osd', 'por')) {
    $Url = "https://raw.githubusercontent.com/tesseract-ocr/tessdata_fast/$TessdataCommit/$Language.traineddata"
    Invoke-WebRequest -Uri $Url -OutFile (Join-Path $Tessdata "$Language.traineddata")
}

$LibreOfficeSource = Join-Path $env:ProgramFiles 'LibreOffice'
Copy-RequiredDirectory $LibreOfficeSource (Join-Path $Tools 'libreoffice')

$PopplerZip = Join-Path $Downloads "Release-$PopplerVersion.zip"
$PopplerUrl = "https://github.com/oschwartz10612/poppler-windows/releases/download/v$PopplerVersion/Release-$PopplerVersion.zip"
Invoke-WebRequest -Uri $PopplerUrl -OutFile $PopplerZip
$PopplerHash = (Get-FileHash -LiteralPath $PopplerZip -Algorithm SHA256).Hash.ToLowerInvariant()
if ($PopplerHash -ne $PopplerSha256) {
    throw "SHA-256 do Poppler nao confere: $PopplerHash"
}
$PopplerExtract = Join-Path $Downloads 'poppler'
Expand-Archive -LiteralPath $PopplerZip -DestinationPath $PopplerExtract -Force
$Pdftoppm = Get-ChildItem -LiteralPath $PopplerExtract -Filter 'pdftoppm.exe' -File -Recurse |
    Select-Object -First 1
if (-not $Pdftoppm) {
    throw 'pdftoppm.exe nao foi encontrado no pacote Poppler.'
}
$PopplerLibrary = $Pdftoppm.Directory.Parent.FullName
Copy-RequiredDirectory $PopplerLibrary (Join-Path $Tools 'poppler')

Copy-RequiredDirectory $env:pythonLocation (Join-Path $Stage 'runtime')
$PackagedPython = Join-Path $Stage 'runtime\python.exe'
$env:PYTHONHOME = Join-Path $Stage 'runtime'
& $PackagedPython -m pip install --disable-pip-version-check --no-warn-script-location --target (Join-Path $Stage 'runtime\Lib\site-packages') -r (Join-Path $Stage 'requirements.txt')
if ($LASTEXITCODE -ne 0) {
    throw 'Falha ao preparar as dependencias Python para Windows.'
}

$env:PATH = @(
    (Join-Path $Tools 'ghostscript\bin'),
    (Join-Path $Tools 'poppler\bin'),
    (Join-Path $Tools 'tesseract'),
    (Join-Path $Tools 'libreoffice\program'),
    (Join-Path $Stage 'runtime'),
    $env:PATH
) -join ';'
$env:TESSDATA_PREFIX = Join-Path $Tools 'tesseract'
$env:UNO_PATH = Join-Path $Tools 'libreoffice\program'

& $PackagedPython -c "import flask, PIL, pypdf, reportlab, cryptography"
if ($LASTEXITCODE -ne 0) { throw 'As dependencias Python empacotadas nao carregaram.' }
& (Join-Path $Tools 'ghostscript\bin\gswin64c.exe') --version
if ($LASTEXITCODE -ne 0) { throw 'Ghostscript empacotado nao iniciou.' }
& (Join-Path $Tools 'poppler\bin\pdftoppm.exe') -v
if ($LASTEXITCODE -ne 0) { throw 'Poppler empacotado nao iniciou.' }
& (Join-Path $Tools 'tesseract\tesseract.exe') --list-langs
if ($LASTEXITCODE -ne 0) { throw 'Tesseract empacotado nao iniciou.' }
& (Join-Path $Tools 'libreoffice\program\soffice.exe') --headless --version
if ($LASTEXITCODE -ne 0) { throw 'LibreOffice empacotado nao iniciou.' }

$Notices = @"
PDF2 Windows portable bundle
Built on $(Get-Date -Format 'yyyy-MM-dd') for Windows x64.

Included components:
- Python 3.13.16 (Python Software Foundation License): https://www.python.org/downloads/release/python-31316/
- Ghostscript $GhostscriptVersion (AGPL or commercial licensing): https://www.ghostscript.com/releases/
- Poppler $PopplerVersion (Windows build from oschwartz10612/poppler-windows): https://github.com/oschwartz10612/poppler-windows/releases
- Tesseract $TesseractVersion (Apache-2.0): https://github.com/tesseract-ocr/tesseract
- Tesseract language data eng/osd/por, pinned at ${TessdataCommit}: https://github.com/tesseract-ocr/tessdata_fast
- LibreOffice $LibreOfficeVersion: https://www.libreoffice.org/download/
- Python packages are listed in requirements.txt and their licenses are included in their distributions.

The Ghostscript AGPL build is included. Review its license terms before redistributing this bundle.
"@
Set-Content -LiteralPath (Join-Path $Stage 'THIRD-PARTY-NOTICES.txt') -Value $Notices -Encoding UTF8

$ZipPath = Join-Path $DistRoot 'PDF2-Windows-portable.zip'
Remove-Item -LiteralPath $ZipPath -Force -ErrorAction SilentlyContinue
Compress-Archive -Path (Join-Path $Stage '*') -DestinationPath $ZipPath -CompressionLevel Optimal
Write-Host "Pacote portatil pronto: $ZipPath"

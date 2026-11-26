<#
.SYNOPSIS
    Arma el paquete sin conexión de SIEASAS Ejecutivo para un Windows Server sin internet.

.DESCRIPTION
    Se ejecuta en un equipo CON internet. Junta en una carpeta (y un .zip):
      codigo\        el repositorio, sin secretos (.env, ca.pem), entornos ni compilados
      web\           la app del ejecutivo compilada (si se indica -Web)
      librerias\     las librerías de Python para Windows x64 y Python 3.12 (pip download)
      instaladores\  Python 3.12.10, URL Rewrite 2.1 y ARR 3.0 para IIS
      CPdescarga.txt catálogo de SEPOMEX (si se indica -Colonias)
      LEEME.txt y SHA256SUMS.txt
    Al final comprueba que las librerías se instalan sin internet en un entorno temporal.

    En el servidor: copiar la carpeta (por ejemplo a C:\SIEASAS), llenar codigo\backend\.env
    y ejecutar como administrador:  .\codigo\windows\instalar.ps1
    instalar.ps1 detecta el paquete e instala Python, URL Rewrite y ARR si faltan.

.EXAMPLE
    .\windows\armar_paquete.ps1 -Web ..\sgsc_ejecutiva\build\web -Colonias C:\descargas\CPdescarga.txt
#>
[CmdletBinding()]
param(
    [string]$Destino = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'paquete_sieasas'),
    # Carpeta build\web compilada con el dominio real; si falta, se agrega después en web\.
    [string]$Web = '',
    # Catálogo de códigos postales de SEPOMEX (CPdescarga.txt).
    [string]$Colonias = '',
    # Python 3.12 de este equipo (para descargar las librerías y verificarlas).
    [string]$Python = '',
    [switch]$SinZip
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'   # Invoke-WebRequest descarga mucho más rápido sin barra de avance
$raiz = Split-Path -Parent $PSScriptRoot
$descargas = @(
    @{ Archivo = 'python-3.12.10-amd64.exe'; Url = 'https://www.python.org/ftp/python/3.12.10/python-3.12.10-amd64.exe' },
    @{ Archivo = 'rewrite_amd64_en-US.msi';  Url = 'https://download.microsoft.com/download/1/2/8/128E2E22-C1B9-44A4-BE2A-5859ED1D4592/rewrite_amd64_en-US.msi' },
    @{ Archivo = 'requestRouter_amd64.msi';  Url = 'https://download.microsoft.com/download/E/9/8/E9849D6A-020E-47E4-9FD0-A023E99B54EB/requestRouter_amd64.msi' }
)
function Paso($texto) { Write-Host ''; Write-Host "== $texto" -ForegroundColor Cyan }
function Ok($texto) { Write-Host "  OK  $texto" -ForegroundColor Green }
function Aviso($texto) { Write-Host "  !!  $texto" -ForegroundColor Yellow }

if (-not $Python) {
    try { $Python = (& py -3.12 -c 'import sys; print(sys.executable)' 2>$null) } catch { $Python = '' }
    if (-not $Python) { $Python = (Get-Command python -ErrorAction Stop).Source }
}
$version = & $Python -c 'import sys; print(''%d.%d'' % sys.version_info[:2])'
if ($version -ne '3.12') { throw "Se requiere Python 3.12 para armar el paquete (encontrado: $version)." }

# Una variable que apunta a un archivo de certificados que ya no existe impide descargar con pip;
# se ignora solo durante este script.
foreach ($variable in 'REQUESTS_CA_BUNDLE', 'CURL_CA_BUNDLE', 'SSL_CERT_FILE', 'PIP_CERT') {
    $valor = [Environment]::GetEnvironmentVariable($variable, 'Process')
    if ($valor -and -not (Test-Path -LiteralPath $valor)) {
        Aviso "$variable apunta a un archivo que no existe ($valor); se ignora en esta ejecución."
        Remove-Item "Env:$variable"
    }
}

if (Test-Path -LiteralPath $Destino) { Remove-Item -LiteralPath $Destino -Recurse -Force }
New-Item -ItemType Directory -Force -Path $Destino | Out-Null
$Destino = (Resolve-Path -LiteralPath $Destino).Path

Paso 'Código'
$codigo = Join-Path $Destino 'codigo'
robocopy $raiz $codigo /E /NFL /NDL /NJH /NJS /NP `
    /XD .git .venv build .dart_tool __pycache__ .pytest_cache logs respaldos node_modules salida evidencias `
    /XF .env ca.pem tools.local.json '*.local.*' '*.zip' | Out-Null
if ($LASTEXITCODE -ge 8) { throw 'No se pudo copiar el código.' }
$secretos = Get-ChildItem -LiteralPath $codigo -Recurse -Force -File | Where-Object { $_.Name -in '.env', 'ca.pem' -or $_.Name -like '*.local.*' }
if ($secretos) { throw ('Se copió un archivo con secretos: ' + ($secretos.FullName -join ', ')) }
$commit = (git -C $raiz rev-parse --short HEAD 2>$null)
$cambios = (git -C $raiz status --porcelain 2>$null)
Ok ("Repositorio en {0}{1}" -f $commit, $(if ($cambios) { ' (con cambios sin confirmar)' } else { '' }))

Paso 'App web'
if ($Web) {
    if (-not (Test-Path -LiteralPath (Join-Path $Web 'index.html'))) { throw "No hay index.html en $Web." }
    robocopy $Web (Join-Path $Destino 'web') /E /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -ge 8) { throw 'No se pudo copiar la app web.' }
    Ok "Copiada de $Web"
} else {
    New-Item -ItemType Directory -Force -Path (Join-Path $Destino 'web') | Out-Null
    Aviso 'Sin app web: compílala con el dominio real y copia build\web dentro de web\ antes de llevar el paquete.'
}

Paso 'Librerías de Python (Windows x64, Python 3.12)'
$librerias = Join-Path $Destino 'librerias'
& $Python -m pip download --disable-pip-version-check --quiet -r (Join-Path $raiz 'backend\requirements.lock.txt') `
    --dest $librerias --only-binary=:all: --platform win_amd64 --python-version 3.12 --implementation cp --abi cp312 --abi abi3 --abi none
if ($LASTEXITCODE -ne 0) { throw 'No se pudieron descargar las librerías.' }
Ok ('{0} archivos' -f (Get-ChildItem $librerias).Count)

Paso 'Instaladores'
$instaladores = Join-Path $Destino 'instaladores'
New-Item -ItemType Directory -Force -Path $instaladores | Out-Null
foreach ($d in $descargas) {
    $archivo = Join-Path $instaladores $d.Archivo
    Invoke-WebRequest -Uri $d.Url -OutFile $archivo -UseBasicParsing
    $firma = Get-AuthenticodeSignature -LiteralPath $archivo
    if ($firma.Status -ne 'Valid') { throw "$($d.Archivo): la firma digital no es válida ($($firma.Status))." }
    Ok ('{0} ({1:N1} MB, firmado por {2})' -f $d.Archivo, ((Get-Item $archivo).Length / 1MB), ($firma.SignerCertificate.Subject -replace '^CN=([^,]+).*', '$1'))
}

Paso 'Colonias'
if ($Colonias) { Copy-Item -LiteralPath $Colonias -Destination (Join-Path $Destino 'CPdescarga.txt'); Ok 'CPdescarga.txt' }
else { Aviso 'Sin CPdescarga.txt: solo hace falta si la base no tiene el catálogo de colonias.' }

Paso 'Verificación: instalar las librerías sin internet'
$prueba = Join-Path ([IO.Path]::GetTempPath()) ('sieasas_venv_' + [guid]::NewGuid().ToString('N'))
try {
    & $Python -m venv $prueba
    & (Join-Path $prueba 'Scripts\python.exe') -m pip install --disable-pip-version-check --quiet --no-index `
        --find-links $librerias -r (Join-Path $raiz 'backend\requirements.lock.txt')
    if ($LASTEXITCODE -ne 0) { throw 'Las librerías del paquete no se instalan sin internet.' }
    Push-Location (Join-Path $raiz 'backend')
    try {
        & (Join-Path $prueba 'Scripts\python.exe') -c 'import fastapi, uvicorn, sqlalchemy, pymysql, cryptography, argon2, bcrypt, pyotp, openpyxl, reportlab; from app.main import app; n = len(app.openapi()[''paths'']); print(''  rutas de la API:'', n); raise SystemExit(0 if n >= 20 else 1)'
        if ($LASTEXITCODE -ne 0) { throw 'La API no carga con las librerías del paquete.' }
    } finally { Pop-Location }
    Ok 'Se instalan sin internet y la API carga'
} finally { Remove-Item -LiteralPath $prueba -Recurse -Force -ErrorAction SilentlyContinue }

Paso 'LEEME y sumas de verificación'
@"
SIEASAS Ejecutivo - paquete de instalación sin conexión
Armado: $(Get-Date -Format 'yyyy-MM-dd HH:mm')   Repositorio: $commit$(if ($cambios) { ' (con cambios sin confirmar)' })

1. Copiar esta carpeta al servidor, por ejemplo a C:\SIEASAS.
2. Copiar codigo\backend\.env.example a codigo\backend\.env y llenar los datos
   (MySQL, CORS_ORIGINS, RESET_URL con el dominio, SMTP). Poner el certificado de MySQL (ca.pem) si usa TLS.
3. Abrir PowerShell como administrador y ejecutar:
     Set-ExecutionPolicy -Scope Process Bypass
     C:\SIEASAS\codigo\windows\instalar.ps1
   Opciones: -MySqlDump <ruta> para respaldar, o -SinRespaldo si TI ya respaldó la base;
             -Certificado <huella> -Dominio <dominio> para el enlace HTTPS.
4. Dar de alta a cada ejecutivo:
     cd C:\SIEASAS\codigo\backend
     .venv\Scripts\python manage.py create-user --correo CORREO --nombres NOMBRES --apellidos APELLIDOS --entidad 19

Contenido: codigo\, web\ (app compilada), librerias\ (Python), instaladores\ (Python 3.12.10, URL Rewrite, ARR),
CPdescarga.txt (si se incluyó). SHA256SUMS.txt permite comprobar que nada cambió en el traslado.
"@ | Set-Content -LiteralPath (Join-Path $Destino 'LEEME.txt') -Encoding UTF8
$sumas = Get-ChildItem -LiteralPath $Destino -Recurse -File | Where-Object { $_.Name -ne 'SHA256SUMS.txt' } | ForEach-Object {
    '{0}  {1}' -f (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLower(), $_.FullName.Substring($Destino.Length + 1)
}
$sumas | Set-Content -LiteralPath (Join-Path $Destino 'SHA256SUMS.txt') -Encoding UTF8
Ok ('{0} archivos' -f $sumas.Count)

if (-not $SinZip) {
    Paso 'Zip'
    $zip = "$Destino.zip"
    if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
    Compress-Archive -Path (Join-Path $Destino '*') -DestinationPath $zip
    Ok ('{0} ({1:N1} MB)' -f $zip, ((Get-Item $zip).Length / 1MB))
}
Write-Host ''
Write-Host "Paquete listo en $Destino" -ForegroundColor Green

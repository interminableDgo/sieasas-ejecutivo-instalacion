# Ensayo de instalación del Ejecutivo sobre la base SSNL de referencia, en un MySQL DE PRUEBA:
#   1. crea una base vacía,
#   2. aplica las migraciones de SSNL (commit de referencia) y las de RBAC de Yii,
#   3. aplica `manage.py migrate` dos veces (debe poder repetirse),
#   4. comprueba que solo se agreguen los 5 catálogos y las 2 columnas de colonia,
#   5. corre las pruebas del backend con MySQL real (RUN_DB_TESTS=1).
#
#   .\pruebas\instalacion\ensayo_instalacion.ps1 -Bd ensayo_sgsc -SsnlRepo C:\ruta\ssnl-gestoria-apoyos `
#       -Php C:\ruta\php.exe -Python C:\ruta\backend\.venv\Scripts\python.exe
#
# Requiere: un MySQL 8 de prueba (por omisión 127.0.0.1:3306, usuario root sin contraseña), el cliente
# mysql en el PATH, PHP 8.2 con pdo_mysql y el repositorio SSNL con su carpeta vendor.
# NUNCA apuntarlo a una base con datos reales: borra y crea la base indicada.
param(
  [Parameter(Mandatory)][string]$Bd,
  [Parameter(Mandatory)][string]$SsnlRepo,
  [string]$SsnlVendor = '',
  [Parameter(Mandatory)][string]$Php,
  # Opciones extra para PHP, p. ej. @('-d','extension=pdo_mysql') si su php.ini no carga la extensión.
  [string[]]$PhpArgs = @(),
  [Parameter(Mandatory)][string]$Python,
  [string]$Servidor = '127.0.0.1',
  [int]$Puerto = 3306,
  [string]$Usuario = 'root',
  [string]$Contrasena = '',
  [string]$Collation = 'utf8mb4_unicode_ci'
)
$ErrorActionPreference = 'Stop'
$aqui = $PSScriptRoot
$backend = Resolve-Path (Join-Path $aqui '..\..\backend')
$salida = Join-Path ([IO.Path]::GetTempPath()) "sgsc-ensayo-$Bd"
New-Item -ItemType Directory -Force $salida | Out-Null

$mysqlArgs = @('-h', $Servidor, '-P', $Puerto, '-u', $Usuario)
if ($Contrasena) { $mysqlArgs += "-p$Contrasena" }
"== 1. Base vacía $Bd ($Collation)"
& mysql @mysqlArgs -e "DROP DATABASE IF EXISTS ``$Bd``; CREATE DATABASE ``$Bd`` CHARACTER SET utf8mb4 COLLATE $Collation;"

$env:DB_HOST = $Servidor; $env:DB_PORT = "$Puerto"; $env:DB_NAME = $Bd
$env:DB_USER = $Usuario; $env:DB_PASSWORD = $Contrasena; $env:DB_SSL = 'false'; $env:DB_SSL_CA = ''
$env:SSNL_REPO = $SsnlRepo
if ($SsnlVendor) { $env:SSNL_VENDOR = $SsnlVendor }
"== 2. Migraciones de SSNL (commit " + (git -C $SsnlRepo rev-parse --short HEAD) + ") y de RBAC de Yii"
& $Php @PhpArgs (Join-Path $aqui 'migrar_ssnl.php') migrate/up --migrationPath=@yii/rbac/migrations --interactive=0 | Select-Object -Last 1
& $Php @PhpArgs (Join-Path $aqui 'migrar_ssnl.php') migrate/up --migrationPath=@app/migrations --interactive=0 | Select-Object -Last 1
& $Python (Join-Path $aqui 'esquema.py') (Join-Path $salida 'antes.json')

"== 3. manage.py migrate (dos veces)"
Push-Location $backend
& $Python manage.py migrate
& $Python manage.py migrate
Pop-Location
& $Python (Join-Path $aqui 'esquema.py') (Join-Path $salida 'despues.json')

"== 4. Cambios sobre la base SSNL"
& $Python (Join-Path $aqui 'diferencia_instalacion.py') (Join-Path $salida 'antes.json') (Join-Path $salida 'despues.json')
if ($LASTEXITCODE -ne 0) { throw 'La instalación cambió algo no previsto en la base SSNL.' }

"== 5. Pruebas del backend con MySQL real"
if (-not $env:AUTH_ENCRYPTION_KEY) {
  $env:AUTH_ENCRYPTION_KEY = & $Python -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"
}
$env:RUN_DB_TESTS = '1'
Push-Location $backend
& $Python -m pytest -q -p no:cacheprovider
$resultado = $LASTEXITCODE
Pop-Location
Remove-Item Env:RUN_DB_TESTS
exit $resultado

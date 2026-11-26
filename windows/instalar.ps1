<#
.SYNOPSIS
    Instala SIEASAS Ejecutivo en Windows Server 2019 sin Docker.

.DESCRIPTION
    La API de Python corre como tarea programada que arranca con el servidor y se reinicia sola;
    IIS entrega la app web y reenvía /auth, /ejecutivo y /health a la API (como gateway/nginx.conf).

    Pasos:
      1. Revisa requisitos: administrador, Python 3.12, backend\.env, certificado de MySQL y app web.
      2. Crea el entorno de Python e instala las librerías (de internet o de -Paquetes).
      3. Prueba la conexión a MySQL.
      4. Respalda la base con mysqldump (o se omite con -SinRespaldo si TI ya lo hizo).
      5. Prepara la base: migrate (5 catálogos y 2 columnas; repetible).
      6. Carga las colonias de SEPOMEX (si se indica -Colonias).
      7. Registra y arranca la API (tarea «SIEASAS API»).
      8. Configura IIS: sitio, app web y web.config.
      9. Verifica la API, la base y la app web.

    Se puede volver a ejecutar: cada paso revisa lo que ya existe.
    No hace: el certificado HTTPS (lo pone TI, o se pasa con -Certificado), abrir puertos en la red
    ni dar de alta ejecutivos (manage.py create-user).

    Sin internet: usar el paquete de armar_paquete.ps1. Si el script está en <paquete>\codigo\windows,
    toma de ahí las librerías, la app web y las colonias, e instala Python 3.12, URL Rewrite y ARR si faltan.

.EXAMPLE
    # Desde el paquete sin conexión copiado a C:\SIEASAS
    C:\SIEASAS\codigo\windows\instalar.ps1 -SinRespaldo

.EXAMPLE
    .\windows\instalar.ps1 -Web C:\sieasas\build\web -Colonias C:\sieasas\CPdescarga.txt -MySqlDump 'C:\Program Files\MySQL\MySQL Server 8.0\bin\mysqldump.exe'
#>
[CmdletBinding()]
param(
    # Carpeta del paquete sin conexión (armar_paquete.ps1). Por omisión se detecta si este script está en <paquete>\codigo\windows.
    [string]$Paquete = '',
    # Carpeta build\web de la app del ejecutivo ya compilada (por omisión, <paquete>\web).
    [string]$Web = '',
    # python.exe 3.12 o posterior; si se omite se busca con «py -3.12» y después «python».
    [string]$Python = '',
    # Carpeta con las librerías descargadas (pip download) para instalar sin internet.
    [string]$Paquetes = '',
    # Catálogo de códigos postales de SEPOMEX (CPdescarga.txt).
    [string]$Colonias = '',
    # mysqldump.exe para respaldar la base antes de cambiarla.
    [string]$MySqlDump = '',
    # Confirma que TI ya respaldó la base y no se hará el respaldo aquí.
    [switch]$SinRespaldo,
    [string]$Sitio = 'SIEASAS',
    [string]$CarpetaSitio = 'C:\inetpub\sieasas',
    [int]$PuertoHttp = 8080,
    [int]$PuertoApi = 8000,
    [int]$Workers = 2,
    # Huella (thumbprint) del certificado HTTPS en el almacén del equipo y su dominio: agrega el enlace 443.
    [string]$Certificado = '',
    [string]$Dominio = ''
)
$ErrorActionPreference = 'Stop'
$raiz = Split-Path -Parent $PSScriptRoot
$backend = Join-Path $raiz 'backend'
$envFile = Join-Path $backend '.env'
$venvPython = Join-Path $backend '.venv\Scripts\python.exe'
$tarea = 'SIEASAS API'

function Paso($n, $texto) { Write-Host ''; Write-Host "[$n/9] $texto" -ForegroundColor Cyan }
function Ok($texto) { Write-Host "  OK  $texto" -ForegroundColor Green }
function Aviso($texto) { Write-Host "  !!  $texto" -ForegroundColor Yellow }
function Falla($texto) { throw "  XX  $texto" }
function Ejecutar($exe, [string[]]$argumentos, $mensaje) {
    & $exe @argumentos
    if ($LASTEXITCODE -ne 0) { Falla $mensaje }
}
function Leer-Env {
    $valores = @{}
    foreach ($linea in Get-Content -LiteralPath $envFile -Encoding UTF8) {
        $l = $linea.Trim()
        if ($l -and -not $l.StartsWith('#') -and $l.Contains('=')) {
            $k, $v = $l.Split('=', 2)
            $valores[$k.Trim()] = $v.Trim().Trim('"').Trim("'")
        }
    }
    $valores
}
function Detener-Api {
    if (Get-ScheduledTask -TaskName $tarea -ErrorAction SilentlyContinue) { Stop-ScheduledTask -TaskName $tarea }
    Get-CimInstance Win32_Process -Filter "Name='python.exe' OR Name='powershell.exe'" |
        Where-Object { $_.CommandLine -and ($_.CommandLine -like "*$backend*") -and $_.ProcessId -ne $PID } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
}

# ------------------------------------------------------------------ 1. requisitos
Paso 1 'Requisitos'
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) { Falla 'Ejecuta PowerShell como administrador.' }
$so = (Get-CimInstance Win32_OperatingSystem).Caption
if ($so -notmatch 'Server') { Aviso "Sistema operativo: $so (el procedimiento está pensado para Windows Server)." } else { Ok $so }

# Paquete sin conexión: librerías, app web, colonias e instaladores salen de ahí.
if (-not $Paquete) {
    $posible = Split-Path -Parent $raiz
    if ((Test-Path (Join-Path $posible 'librerias')) -and (Test-Path (Join-Path $posible 'instaladores'))) { $Paquete = $posible }
}
$instaladores = ''
if ($Paquete) {
    $Paquete = (Resolve-Path -LiteralPath $Paquete).Path
    if (-not $Paquetes) { $Paquetes = Join-Path $Paquete 'librerias' }
    if (-not $Web) { $Web = Join-Path $Paquete 'web' }
    if (-not $Colonias -and (Test-Path (Join-Path $Paquete 'CPdescarga.txt'))) { $Colonias = Join-Path $Paquete 'CPdescarga.txt' }
    $instaladores = Join-Path $Paquete 'instaladores'
    Ok "Paquete sin conexión: $Paquete"
}
if (-not $Web) { Falla 'Indica -Web con la carpeta build\web compilada (o usa el paquete de armar_paquete.ps1).' }
function Instalador($patron) {
    if (-not $instaladores) { return $null }
    Get-ChildItem -Path (Join-Path $instaladores $patron) -ErrorAction SilentlyContinue | Select-Object -First 1
}

function Buscar-Python {
    $comun = "$env:ProgramFiles\Python312\python.exe"
    if (Test-Path $comun) { return $comun }
    if (Get-Command py -ErrorAction SilentlyContinue) {
        try { $r = (& py -3.12 -c 'import sys; print(sys.executable)' 2>$null); if ($r -and (Test-Path $r)) { return $r } } catch { }
    }
    return $null
}
if (-not $Python) { $Python = Buscar-Python }
if (-not $Python) {
    $exe = Instalador 'python-3.12*-amd64.exe'
    if ($exe) {
        Write-Host "  ..  Instalando $($exe.Name) para todos los usuarios"
        $p = Start-Process -FilePath $exe.FullName -ArgumentList '/quiet', 'InstallAllUsers=1', 'PrependPath=1', 'Include_test=0', 'Include_launcher=1' -Wait -PassThru
        if ($p.ExitCode -ne 0) { Falla "La instalación de Python terminó con código $($p.ExitCode)." }
        $Python = Buscar-Python
    }
}
if (-not $Python -or -not (Test-Path -LiteralPath $Python)) { Falla 'No se encontró Python 3.12. Instálalo (para todos los usuarios), indica -Python o usa el paquete sin conexión.' }
# Windows PowerShell 5.1 no escapa comillas dobles al pasar argumentos: el código de Python usa solo comillas simples.
$version = & $Python -c 'import sys; print(''%d.%d'' % sys.version_info[:2])'
if ([version]$version -lt [version]'3.12') { Falla "Python $version; se requiere 3.12 o posterior." }
Ok "Python $version ($Python)"

if (-not (Test-Path -LiteralPath $envFile)) { Falla 'Falta backend\.env. Cópialo de backend\.env.example y llena los datos.' }
$cfg = Leer-Env
$faltan = @('DB_HOST', 'DB_PORT', 'DB_NAME', 'DB_USER', 'DB_PASSWORD', 'CORS_ORIGINS', 'RESET_URL') |
    Where-Object { -not $cfg[$_] -or $cfg[$_] -eq 'TU_PASSWORD' }
if ($faltan) { Falla ('Faltan datos en backend\.env: ' + ($faltan -join ', ')) }
if ($cfg['RESET_URL'] -match '127\.0\.0\.1|localhost' -or $cfg['CORS_ORIGINS'] -match '127\.0\.0\.1|localhost') {
    Aviso 'RESET_URL o CORS_ORIGINS todavía apuntan a esta máquina; deben llevar el dominio institucional (https://...).'
}
if (-not $cfg['SMTP_HOST'] -or -not $cfg['SMTP_FROM']) { Aviso 'Sin datos SMTP: la recuperación de contraseña no enviará correos.' }
if ($cfg['DB_SSL'] -eq 'true') {
    $ca = $cfg['DB_SSL_CA']
    if ($ca -and -not [IO.Path]::IsPathRooted($ca)) { $ca = Join-Path $backend $ca }
    if (-not $ca -or -not (Test-Path -LiteralPath $ca)) { Falla "DB_SSL=true pero no existe el certificado de MySQL (DB_SSL_CA=$($cfg['DB_SSL_CA']))." }
    Ok "Certificado de MySQL: $ca"
}
if (-not $cfg['AUTH_ENCRYPTION_KEY']) {
    # Clave de cifrado del segundo factor: se genera una vez y se guarda en .env.
    $clave = & $Python -c 'import base64, os; print(base64.urlsafe_b64encode(os.urandom(32)).decode())'
    $texto = Get-Content -LiteralPath $envFile -Raw -Encoding UTF8
    if ($texto -match '(?m)^AUTH_ENCRYPTION_KEY=.*$') { $texto = $texto -replace '(?m)^AUTH_ENCRYPTION_KEY=.*$', "AUTH_ENCRYPTION_KEY=$clave" }
    else { $texto = $texto.TrimEnd() + "`r`nAUTH_ENCRYPTION_KEY=$clave`r`n" }
    [IO.File]::WriteAllText($envFile, $texto, (New-Object Text.UTF8Encoding $false))
    Ok 'AUTH_ENCRYPTION_KEY generada y guardada en backend\.env (respáldala: sin ella no se descifra el segundo factor).'
}
# Solo administradores y SYSTEM pueden leer .env (contiene contraseñas).
icacls $envFile /inheritance:r /grant:r '*S-1-5-32-544:(F)' '*S-1-5-18:(R)' | Out-Null
Ok 'backend\.env completo y protegido'

if (-not (Test-Path -LiteralPath (Join-Path $Web 'index.html'))) { Falla "No hay index.html en $Web (carpeta build\web compilada)." }
Ok "App web: $Web"

# ------------------------------------------------------------------ 2. entorno de Python
Paso 2 'Entorno de Python y librerías'
Detener-Api
if (-not (Test-Path -LiteralPath $venvPython)) { Ejecutar $Python @('-m', 'venv', (Join-Path $backend '.venv')) 'No se pudo crear el entorno de Python.' }
$pip = @('-m', 'pip', 'install', '--disable-pip-version-check', '-r', (Join-Path $backend 'requirements.lock.txt'))
if ($Paquetes) { $pip += @('--no-index', '--find-links', $Paquetes) }
Ejecutar $venvPython $pip 'No se pudieron instalar las librerías (revisa internet o -Paquetes).'
Ok 'Librerías instaladas'

# ------------------------------------------------------------------ 3. conexión
Paso 3 'Conexión a MySQL'
Push-Location $backend
try {
    Ejecutar $venvPython @('-c', 'from sqlalchemy import text; from app.database import engine; c = engine.connect(); print(''  MySQL'', c.execute(text(''SELECT VERSION()'')).scalar()); c.close()') 'No se pudo conectar a MySQL con los datos de backend\.env.'
    # En Windows, MySQL puede guardar los nombres de tabla en minúsculas: se comparan sin distinguir.
    Ejecutar $venvPython @('-c', 'from sqlalchemy import text; from app.database import engine; c = engine.connect(); t = {r[0].lower() for r in c.execute(text(''SHOW TABLES''))}; c.close(); raise SystemExit(0 if {''tbl_users'', ''tbl_solicitudesapoyo'', ''inegi_cat_municipios''} <= t else 1)') 'La base no tiene las tablas de SSNL (Tbl_Users, Tbl_SolicitudesApoyo, INEGI_Cat_Municipios).'
} finally { Pop-Location }
Ok "Base $($cfg['DB_NAME']) en $($cfg['DB_HOST']) con el esquema SSNL"

# ------------------------------------------------------------------ 4. respaldo
Paso 4 'Respaldo de la base'
if ($SinRespaldo) {
    Aviso 'Se omite: TI confirmó que ya respaldó la base.'
} else {
    if (-not $MySqlDump) { $cmd = Get-Command mysqldump -ErrorAction SilentlyContinue; if ($cmd) { $MySqlDump = $cmd.Source } }
    if (-not $MySqlDump -or -not (Test-Path -LiteralPath $MySqlDump)) {
        Falla 'No se encontró mysqldump. Indica -MySqlDump, o usa -SinRespaldo si TI ya respaldó la base.'
    }
    $carpeta = Join-Path $backend 'respaldos'
    New-Item -ItemType Directory -Force -Path $carpeta | Out-Null
    $archivo = Join-Path $carpeta ('{0}_{1}.sql' -f $cfg['DB_NAME'], (Get-Date -Format 'yyyyMMdd_HHmm'))
    $argumentos = @('-h', $cfg['DB_HOST'], '-P', $cfg['DB_PORT'], '-u', $cfg['DB_USER'], '--single-transaction',
                    '--routines', '--triggers', '--result-file', $archivo)
    if ($cfg['DB_SSL'] -eq 'true') { $argumentos += @('--ssl-mode=VERIFY_CA', "--ssl-ca=$ca") }
    $argumentos += $cfg['DB_NAME']
    $env:MYSQL_PWD = $cfg['DB_PASSWORD']   # la contraseña no aparece en la línea de comandos
    try { Ejecutar $MySqlDump $argumentos 'Falló el respaldo; no se modificó la base.' } finally { Remove-Item Env:MYSQL_PWD }
    Ok ('Respaldo: {0} ({1:N1} MB)' -f $archivo, ((Get-Item $archivo).Length / 1MB))
}

# ------------------------------------------------------------------ 5 y 6. base
Paso 5 'Preparar la base (migrate)'
Push-Location $backend
try {
    Ejecutar $venvPython @('manage.py', 'migrate') 'Falló la migración.'
    Paso 6 'Colonias de SEPOMEX'
    if ($Colonias) { Ejecutar $venvPython @('manage.py', 'cargar-colonias', $Colonias, '--estado', '19') 'Falló la carga de colonias.' }
    else { Aviso 'Se omite: no se indicó -Colonias (CPdescarga.txt). El registro necesita el catálogo de colonias.' }
} finally { Pop-Location }

# ------------------------------------------------------------------ 7. API
Paso 7 'API como tarea de inicio'
$script = Join-Path $PSScriptRoot 'api.ps1'
$accion = New-ScheduledTaskAction -Execute 'powershell.exe' -WorkingDirectory $backend `
    -Argument ('-NoProfile -ExecutionPolicy Bypass -File "{0}" -Backend "{1}" -Puerto {2} -Workers {3}' -f $script, $backend, $PuertoApi, $Workers)
$ajustes = New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 999 `
    -RestartInterval (New-TimeSpan -Minutes 1) -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
$cuenta = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
Register-ScheduledTask -TaskName $tarea -Action $accion -Trigger (New-ScheduledTaskTrigger -AtStartup) `
    -Settings $ajustes -Principal $cuenta -Description 'API de SIEASAS Ejecutivo (FastAPI en 127.0.0.1)' -Force | Out-Null
Start-ScheduledTask -TaskName $tarea
Ok "Tarea «$tarea» registrada y en marcha (bitácora: backend\logs\api.log)"

# ------------------------------------------------------------------ 8. IIS
Paso 8 'IIS'
$caracteristicas = 'Web-Server', 'Web-Static-Content', 'Web-Default-Doc', 'Web-Http-Errors', 'Web-Http-Logging',
                   'Web-Stat-Compression', 'Web-Filtering', 'Web-Mgmt-Console'
if (Get-Command Install-WindowsFeature -ErrorAction SilentlyContinue) {
    $faltantes = $caracteristicas | Where-Object { -not (Get-WindowsFeature $_).Installed }
    if ($faltantes) { Install-WindowsFeature $faltantes | Out-Null; Ok ('IIS: se instaló ' + ($faltantes -join ', ')) } else { Ok 'IIS instalado' }
} elseif (-not (Test-Path "$env:SystemRoot\System32\inetsrv\w3wp.exe")) {
    Falla 'IIS no está instalado.'
}
$rewrite = "$env:SystemRoot\System32\inetsrv\rewrite.dll"
$arr = "$env:ProgramFiles\IIS\Application Request Routing\requestRouter.dll"
# URL Rewrite va antes que ARR, que depende de él.
foreach ($m in @(@{ Dll = $rewrite; Msi = 'rewrite_amd64*.msi' }, @{ Dll = $arr; Msi = 'requestRouter_amd64*.msi' })) {
    $msi = Instalador $m.Msi
    if (-not (Test-Path $m.Dll) -and $msi) {
        Write-Host "  ..  Instalando $($msi.Name)"
        $p = Start-Process msiexec.exe -ArgumentList '/i', "`"$($msi.FullName)`"", '/qn', '/norestart' -Wait -PassThru
        if ($p.ExitCode -notin 0, 3010) { Falla "La instalación de $($msi.Name) terminó con código $($p.ExitCode)." }
    }
}
$sinModulos = @()
if (-not (Test-Path $rewrite)) { $sinModulos += 'URL Rewrite 2.1' }
if (-not (Test-Path $arr)) { $sinModulos += 'Application Request Routing 3.0' }
if ($sinModulos) { Falla ('Faltan módulos de IIS (instaladores .msi de Microsoft): ' + ($sinModulos -join ' y ')) }
Ok 'URL Rewrite y ARR instalados'

Import-Module WebAdministration
# ARR como proxy: reenvía a la API; 2 minutos de espera para las exportaciones.
Set-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Filter 'system.webServer/proxy' -Name 'enabled' -Value $true
Set-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Filter 'system.webServer/proxy' -Name 'timeout' -Value '00:02:00'
# La API limita los intentos por IP (app/security.py) y la toma de X-Forwarded-For (uvicorn --proxy-headers).
# ARR agrega el puerto del cliente por omisión; sin él, la IP es estable entre conexiones.
Set-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Filter 'system.webServer/proxy' -Name 'includePortInXForwardedFor' -Value $false

New-Item -ItemType Directory -Force -Path $CarpetaSitio | Out-Null
robocopy $Web $CarpetaSitio /MIR /XF web.config /NFL /NDL /NJH /NJS /NP | Out-Null
if ($LASTEXITCODE -ge 8) { Falla 'No se pudo copiar la app web.' }
$config = (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'web.config') -Raw -Encoding UTF8).Replace('{{PUERTO_API}}', "$PuertoApi")
[IO.File]::WriteAllText((Join-Path $CarpetaSitio 'web.config'), $config, (New-Object Text.UTF8Encoding $false))

if (-not (Test-Path "IIS:\AppPools\$Sitio")) { New-WebAppPool -Name $Sitio | Out-Null }
Set-ItemProperty "IIS:\AppPools\$Sitio" -Name managedRuntimeVersion -Value ''
if (Test-Path "IIS:\Sites\$Sitio") {
    Set-ItemProperty "IIS:\Sites\$Sitio" -Name physicalPath -Value $CarpetaSitio
} else {
    $ocupado = Get-WebBinding | Where-Object { $_.bindingInformation -like "*:${PuertoHttp}:*" }
    if ($ocupado) { Falla "El puerto $PuertoHttp ya lo usa otro sitio de IIS; indica otro con -PuertoHttp." }
    New-Website -Name $Sitio -PhysicalPath $CarpetaSitio -Port $PuertoHttp -ApplicationPool $Sitio | Out-Null
}
# La bitácora de IIS no guarda la consulta (?reset_token=...), igual que el gateway.
$campos = (Get-ItemProperty "IIS:\Sites\$Sitio" -Name logFile).logExtFileFlags -replace 'UriQuery,?', ''
Set-ItemProperty "IIS:\Sites\$Sitio" -Name logFile.logExtFileFlags -Value $campos.TrimEnd(',')
if ($Certificado) {
    if (-not $Dominio) { Falla 'Con -Certificado indica también -Dominio.' }
    if (-not (Get-WebBinding -Name $Sitio -Protocol https -Port 443 -HostHeader $Dominio)) {
        New-WebBinding -Name $Sitio -Protocol https -Port 443 -HostHeader $Dominio -SslFlags 1
    }
    (Get-WebBinding -Name $Sitio -Protocol https -Port 443 -HostHeader $Dominio).AddSslCertificate($Certificado, 'My')
    Ok "HTTPS: https://$Dominio"
} else {
    Aviso 'Sin HTTPS: TI debe agregar al sitio el enlace 443 con el certificado del dominio (o volver a ejecutar con -Certificado y -Dominio).'
}
Start-Website -Name $Sitio
Ok "Sitio «$Sitio» en http://localhost:$PuertoHttp -> $CarpetaSitio"

# ------------------------------------------------------------------ 9. verificación
Paso 9 'Verificación'
function Probar($url) {
    for ($i = 0; $i -lt 30; $i++) {
        try { return Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 10 } catch { Start-Sleep -Seconds 2 }
    }
    return $null
}
$errores = 0
foreach ($prueba in @(
        @{ Nombre = 'API';                 Url = "http://127.0.0.1:$PuertoApi/health" },
        @{ Nombre = 'API con MySQL';       Url = "http://127.0.0.1:$PuertoApi/health/db" },
        @{ Nombre = 'IIS -> API -> MySQL'; Url = "http://localhost:$PuertoHttp/health/db" },
        @{ Nombre = 'App web en IIS';      Url = "http://localhost:$PuertoHttp/" })) {
    $r = Probar $prueba.Url
    if ($r -and $r.StatusCode -eq 200) { Ok "$($prueba.Nombre): $($prueba.Url)" }
    else { Aviso "$($prueba.Nombre): sin respuesta correcta en $($prueba.Url)"; $errores++ }
}
Write-Host ''
if ($errores) { Write-Host "Instalación con $errores verificaciones fallidas. Revisa backend\logs\api.log y la bitácora de IIS." -ForegroundColor Red; exit 1 }
Write-Host 'Instalación completa.' -ForegroundColor Green
Write-Host 'Siguiente: dar de alta a cada ejecutivo con'
Write-Host '  cd backend; .venv\Scripts\python manage.py create-user --correo CORREO --nombres NOMBRES --apellidos APELLIDOS --entidad 19'

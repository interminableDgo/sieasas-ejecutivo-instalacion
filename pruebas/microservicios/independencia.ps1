# Pruebas de independencia de los cuatro microservicios con Docker Compose en ejecución.
# Solo hace GET y operaciones de contenedores (detener, iniciar, reconstruir); no escribe en
# la base de datos. Compatible con Windows PowerShell 5.1 y PowerShell 7.
#
#   docker compose --env-file backend/.env up -d --build
#   $env:SGSC_TEST_TOKEN = '<token de sesión>'   # opcional; sin él se espera 401 en vez de 200
#   .\pruebas\microservicios\independencia.ps1
param([string]$Gateway = 'http://localhost:8080', [string]$EnvFile = 'backend/.env')
$ErrorActionPreference = 'Stop'
Set-Location (Resolve-Path (Join-Path $PSScriptRoot '..\..'))
$compose = @('compose', '--env-file', $EnvFile)
$headers = @{}
if ($env:SGSC_TEST_TOKEN) { $headers['Authorization'] = "Bearer $env:SGSC_TEST_TOKEN" }
$ok = if ($env:SGSC_TEST_TOKEN) { 200 } else { 401 }
$rutas = [ordered]@{
    indicadores = '/ejecutivo/dashboard'
    detalle     = '/ejecutivo/solicitudes'
    registro    = '/ejecutivo/colonias?municipio_id=1'
    reportes    = '/ejecutivo/exportar/pdf'
}
$fallas = 0

# Docker escribe su progreso («Container … Stopping») en stderr. En Windows PowerShell 5.1,
# con $ErrorActionPreference = 'Stop', cada línea de stderr de un programa nativo se convierte
# en un error terminante. Aquí stderr se separa de la salida y el éxito se decide por el código
# de salida: el progreso no detiene el script y un fallo real de Docker sí lo hace.
function Invoke-Docker([string[]]$Argumentos, [switch]$PermitirFallo) {
    $anterior = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $salida = & docker @Argumentos 2>&1
        $codigo = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $anterior
    }
    $errores = @($salida | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] } | ForEach-Object { "$_" })
    if ($codigo -ne 0 -and -not $PermitirFallo) {
        throw "docker $($Argumentos -join ' ') terminó con código $codigo.`n$($errores -join "`n")"
    }
    @($salida | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] } | ForEach-Object { "$_" })
}

function Compose([string[]]$Argumentos, [switch]$PermitirFallo) {
    Invoke-Docker -Argumentos ($compose + $Argumentos) -PermitirFallo:$PermitirFallo
}

function Estado($ruta) {
    try { (Invoke-WebRequest "$Gateway$ruta" -Headers $headers -UseBasicParsing -TimeoutSec 120).StatusCode }
    catch { [int]$_.Exception.Response.StatusCode }
}
function Verificar($condicion, $mensaje) {
    if ($condicion) { Write-Output "OK    $mensaje" } else { Write-Output "FALLA $mensaje"; $script:fallas++ }
}
function Contenedor($servicio) {
    (Compose @('ps', '-q', $servicio)) | Where-Object { $_ } | Select-Object -First 1
}
function Esperar-Saludable($servicio) {
    for ($i = 0; $i -lt 30; $i++) {
        $id = Contenedor $servicio
        if ($id -and (Invoke-Docker @('inspect', '-f', '{{.State.Health.Status}}', $id)) -eq 'healthy') { return }
        Start-Sleep -Seconds 2
    }
    throw "$servicio no quedó healthy."
}
# Docker Compose v5 devuelve «:0» (y versiones anteriores, un error) para un puerto no publicado.
function Puerto-Publicado($servicio, $puerto) {
    $salida = Compose @('port', $servicio, "$puerto") -PermitirFallo
    @($salida | ForEach-Object { $_.Trim() } | Where-Object { $_ -and $_ -ne ':0' -and $_ -notmatch ':0$' })
}

# 1. Con un servicio detenido, los otros tres siguen respondiendo y el suyo responde 503.
foreach ($detenido in $rutas.Keys) {
    Compose @('stop', $detenido) | Out-Null
    Start-Sleep -Seconds 3
    foreach ($s in $rutas.Keys) {
        $codigo = Estado $rutas[$s]
        if ($s -eq $detenido) { Verificar ($codigo -eq 503) "$detenido detenido: $($rutas[$s]) -> $codigo (esperado 503)" }
        else { Verificar ($codigo -eq $ok) "$detenido detenido: $s sigue respondiendo $codigo" }
    }
    Compose @('start', $detenido) | Out-Null
    Esperar-Saludable $detenido
}

# 2. Reconstruir y reiniciar un servicio no reinicia los demás.
$antes = @{}
foreach ($s in 'gateway', 'nucleo', 'indicadores', 'registro', 'reportes') {
    $antes[$s] = Invoke-Docker @('inspect', '-f', '{{.State.StartedAt}}', (Contenedor $s))
}
Compose @('up', '-d', '--no-deps', '--build', 'detalle') | Out-Null
Esperar-Saludable 'detalle'
foreach ($s in $antes.Keys) {
    $despues = Invoke-Docker @('inspect', '-f', '{{.State.StartedAt}}', (Contenedor $s))
    Verificar ("$despues" -eq "$($antes[$s])") "reconstruir detalle no reinicia $s"
}

# 3. Solo el gateway publica puertos y ninguna imagen contiene .env ni ca.pem.
Verificar ((Puerto-Publicado 'gateway' 80).Count -eq 1) 'el gateway publica su puerto'
foreach ($s in 'nucleo', 'indicadores', 'detalle', 'registro', 'reportes') {
    $puertos = Puerto-Publicado $s 8000
    Verificar ($puertos.Count -eq 0) "$s no publica puertos $($puertos -join ', ')"
    $archivos = Invoke-Docker @('run', '--rm', '--entrypoint', 'sh', "sgsc-$s", '-c',
        "find / -xdev \( -name '.env' -o -name '*.pem' -o -name 'ca.pem' \) -not -path '/proc/*' -not -path '/usr/*' -not -path '/etc/ssl/*' 2>/dev/null") -PermitirFallo
    Verificar (-not ($archivos | Where-Object { $_ })) "la imagen sgsc-$s no contiene .env ni certificados $($archivos -join ', ')"
}
foreach ($s in 'indicadores', 'detalle', 'registro', 'reportes') {
    $variables = Invoke-Docker @('inspect', '-f', '{{range .Config.Env}}{{println .}}{{end}}', (Contenedor $s)) |
        Where-Object { $_ -match '^(SMTP_|AUTH_ENCRYPTION_KEY|RESET_URL)' } | ForEach-Object { ($_ -split '=')[0] }
    Verificar (-not $variables) "$s no recibe secretos del núcleo $($variables -join ', ')"
}

Write-Output "`nFallas: $fallas"
if ($fallas) { exit 1 }

# Ejecuta, sin Docker y sin base de datos, las pruebas de sgsc_common, de cada microservicio
# del Ejecutivo y del gateway. Cada servicio usa su propio entorno virtual con únicamente sus
# dependencias y la librería transversal: si una prueba pasa, el servicio no necesita el
# monolito (app/) ni el código de los otros tres servicios.
#
#   .\pruebas\microservicios\ejecutar_pruebas_locales.ps1            # crea los entornos si faltan
#   .\pruebas\microservicios\ejecutar_pruebas_locales.ps1 -Recrear   # los vuelve a crear
#
# Las variables DB_* apuntan a un servidor inexistente para garantizar que ninguna prueba
# toque Aiven. Los resultados se guardan en pruebas/microservicios/evidencias/.
param([switch]$Recrear, [string]$Python = 'python')
$ErrorActionPreference = 'Stop'
$root = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$backend = Join-Path $root 'backend'
$evidencias = Join-Path $PSScriptRoot 'evidencias'
New-Item -ItemType Directory -Force $evidencias | Out-Null

$env:DB_HOST = 'db.invalid'; $env:DB_PORT = '1'; $env:DB_USER = 'sin-acceso'; $env:DB_PASSWORD = 'sin-acceso'
$env:DB_SSL = 'false'; $env:RUN_DB_TESTS = ''; $env:SGSC_ENV_FILE = ''
$env:PYTHONIOENCODING = 'utf-8'

function Invoke-Suite($nombre, $carpeta, $requisitos) {
    $venv = Join-Path $carpeta '.venv'
    $py = Join-Path $venv 'Scripts\python.exe'
    if ($Recrear -and (Test-Path $venv)) { Remove-Item -Recurse -Force $venv }
    if (!(Test-Path $py)) {
        & $Python -m venv $venv
        $paquetes = @()
        foreach ($r in $requisitos) { $paquetes += @('-r', $r) }
        & $py -m pip install -q --disable-pip-version-check @paquetes (Join-Path $backend 'libs\sgsc_common')
        if ($LASTEXITCODE -ne 0) { throw "No se pudieron instalar las dependencias de $nombre." }
    }
    $salida = Join-Path $evidencias "pytest_$nombre.txt"
    Push-Location $carpeta
    try {
        & $py -m pytest -q -p no:cacheprovider 2>&1 | Tee-Object -FilePath $salida | Select-Object -Last 3
        $codigo = $LASTEXITCODE
    } finally { Pop-Location }
    [pscustomobject]@{ Suite = $nombre; Resultado = $(if ($codigo -eq 0) { 'OK' } else { "FALLA ($codigo)" }) }
}

$resultados = @()
$servicios = Join-Path $backend 'services'
$resultados += Invoke-Suite 'sgsc_common' (Join-Path $backend 'libs\sgsc_common') @(
    (Join-Path $servicios 'indicadores\requirements.txt'), (Join-Path $servicios 'indicadores\requirements-test.txt'))
foreach ($s in 'indicadores', 'detalle', 'registro', 'reportes') {
    $carpeta = Join-Path $servicios $s
    $resultados += Invoke-Suite $s $carpeta @((Join-Path $carpeta 'requirements.txt'), (Join-Path $carpeta 'requirements-test.txt'))
}
$resultados += Invoke-Suite 'gateway' (Join-Path $root 'gateway') @((Join-Path $servicios 'indicadores\requirements-test.txt'))
# Paridad monolito/microservicios: necesita las dependencias del monolito (requirements.lock.txt).
$resultados += Invoke-Suite 'paridad_codigo' (Join-Path $PSScriptRoot 'codigo') @((Join-Path $backend 'requirements.lock.txt'))
# Regresión del monolito (Render): sus pruebas deben seguir pasando sin cambios.
$resultados += Invoke-Suite 'monolito' $backend @((Join-Path $backend 'requirements.lock.txt'))
$resultados | Format-Table -AutoSize | Out-String | Tee-Object -FilePath (Join-Path $evidencias 'resumen_pruebas_locales.txt')
if ($resultados.Resultado -ne 'OK') { exit 1 }

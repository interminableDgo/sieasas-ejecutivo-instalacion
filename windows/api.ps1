# Mantiene encendida la API de SIEASAS en Windows: si el proceso termina, lo vuelve a iniciar.
# Lo ejecuta la tarea programada «SIEASAS API» que crea instalar.ps1 al arrancar el servidor.
param(
    [Parameter(Mandatory)][string]$Backend,
    [int]$Puerto = 8000,
    [int]$Workers = 2
)
$ErrorActionPreference = 'Continue'
Set-Location -LiteralPath $Backend
$python = Join-Path $Backend '.venv\Scripts\python.exe'
$logs = Join-Path $Backend 'logs'
New-Item -ItemType Directory -Force -Path $logs | Out-Null
$bitacora = Join-Path $logs 'api.log'

while ($true) {
    Add-Content -LiteralPath $bitacora -Value ('{0} Inicia la API en 127.0.0.1:{1}' -f (Get-Date -Format s), $Puerto)
    # Sin bitácora de accesos de uvicorn: IIS ya registra las peticiones (sin la consulta, que puede llevar el token de recuperación).
    & $python -m uvicorn app.main:app --host 127.0.0.1 --port $Puerto --workers $Workers --no-access-log `
        --proxy-headers --forwarded-allow-ips 127.0.0.1 2>&1 |
        ForEach-Object { Add-Content -LiteralPath $bitacora -Value $_.ToString() }
    Add-Content -LiteralPath $bitacora -Value ('{0} La API terminó (código {1}); se reinicia en 5 s.' -f (Get-Date -Format s), $LASTEXITCODE)
    Start-Sleep -Seconds 5
}

param([switch]$Recompilar, [string]$Flutter)
$ErrorActionPreference = 'Stop'
$projectRoot = $PSScriptRoot
$backendRoot = Join-Path $projectRoot 'backend'
$pythonExe = Join-Path $backendRoot '.venv\Scripts\python.exe'
if (!(Test-Path -LiteralPath $pythonExe)) { throw 'Primero instala las dependencias según backend/README.md.' }
if ($Recompilar) {
    if (!$Flutter) {
        $command = Get-Command flutter -ErrorAction SilentlyContinue
        if ($command) { $Flutter = $command.Source }
        elseif (Test-Path (Join-Path $projectRoot 'tools.local.json')) {
            $Flutter = (Get-Content (Join-Path $projectRoot 'tools.local.json') | ConvertFrom-Json).flutter
        }
    }
    if (!$Flutter) { throw 'Indica la ruta de flutter.bat con -Flutter.' }
    Push-Location (Join-Path $projectRoot 'sgsc_ejecutiva')
    try {
        & $Flutter build web --no-pub --dart-define=API_BASE_URL=http://127.0.0.1:8000
        if ($LASTEXITCODE -ne 0) { throw 'No se pudo compilar Flutter.' }
    } finally { Pop-Location }
}
if (!(Test-Path (Join-Path $projectRoot 'sgsc_ejecutiva\build\web\index.html'))) { throw 'Ejecuta iniciar.ps1 -Recompilar.' }
if (!(Get-NetTCPConnection -LocalPort 8000 -State Listen -ErrorAction SilentlyContinue)) {
    Start-Process -FilePath $pythonExe -ArgumentList '-m','uvicorn','app.main:app','--host','127.0.0.1','--port','8000' -WorkingDirectory $backendRoot -WindowStyle Hidden -RedirectStandardOutput (Join-Path $backendRoot 'api.local.log') -RedirectStandardError (Join-Path $backendRoot 'api-error.local.log')
}
if (!(Get-NetTCPConnection -LocalPort 5173 -State Listen -ErrorAction SilentlyContinue)) {
    Start-Process -FilePath $pythonExe -ArgumentList 'serve_web.py' -WorkingDirectory $backendRoot -WindowStyle Hidden -RedirectStandardOutput (Join-Path $backendRoot 'web.local.log') -RedirectStandardError (Join-Path $backendRoot 'web-error.local.log')
}
Write-Output 'SIESAS Ejecutivo: https://127.0.0.1:5173'

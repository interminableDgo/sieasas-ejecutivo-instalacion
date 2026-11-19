# Mide la pantalla de inicio de sesión con Lighthouse 13.6.0: tres corridas por modo y la mediana.
# Requisitos: Node.js, Microsoft Edge y la app servida con serve_web.py (https://127.0.0.1:5173).
#   cd backend; .venv\Scripts\python.exe serve_web.py
#   .\pruebas\lighthouse\ejecutar_lighthouse.ps1 -Modo mobile
#   .\pruebas\lighthouse\ejecutar_lighthouse.ps1 -Modo desktop
param(
  [ValidateSet('mobile', 'desktop')][string]$Modo = 'mobile',
  [int]$Veces = 3,
  [string]$Url = 'https://127.0.0.1:5173/',
  [string]$Salida = (Join-Path $PSScriptRoot 'reportes\ultima')
)
$ErrorActionPreference = 'Continue'
if (-not $env:CHROME_PATH) {
  $env:CHROME_PATH = 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe'
}
New-Item -ItemType Directory -Force $Salida | Out-Null
# serve_web.py usa un certificado autofirmado: el navegador de la prueba lo acepta.
$navegador = '--headless=new --ignore-certificate-errors'
$perfil = if ($Modo -eq 'desktop') { '--preset=desktop' } else { '--form-factor=mobile' }
$filas = @()
for ($i = 1; $i -le $Veces; $i++) {
  $base = Join-Path $Salida "$Modo-$i"
  npx -y lighthouse@13.6.0 $Url $perfil --output=json --output=html --output-path=$base --quiet `
    --chrome-flags=$navegador 2>$null | Out-Null
  $j = Get-Content "$base.report.json" -Raw | ConvertFrom-Json
  $a = $j.audits
  $filas += [pscustomobject]@{
    corrida         = $i
    rendimiento     = [int]($j.categories.performance.score * 100)
    accesibilidad   = [int]($j.categories.accessibility.score * 100)
    buenasPracticas = [int]($j.categories.'best-practices'.score * 100)
    seo             = [int]($j.categories.seo.score * 100)
    FCP             = $a.'first-contentful-paint'.displayValue
    LCP             = $a.'largest-contentful-paint'.displayValue
    TBT             = $a.'total-blocking-time'.displayValue
    SI              = $a.'speed-index'.displayValue
    CLS             = $a.'cumulative-layout-shift'.displayValue
  }
}
$filas | Format-Table -AutoSize | Out-String -Width 200
$mediana = ($filas | Sort-Object rendimiento)[[int][math]::Floor($Veces / 2)]
"Mediana de rendimiento ($Modo): $($mediana.rendimiento) (corrida $($mediana.corrida))"

param([switch]$CheckOnly)
$ErrorActionPreference='Stop'
try {
    $cfg=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'runtime.json') -Raw | ConvertFrom-Json
    if ($CheckOnly) { & $cfg.node (Join-Path $PSScriptRoot 'reconnect.cjs') --check }
    else { & $cfg.node (Join-Path $PSScriptRoot 'reconnect.cjs') --test }
    exit $LASTEXITCODE
} catch { Write-Host 'Run install.cmd successfully first.'; exit 1 }

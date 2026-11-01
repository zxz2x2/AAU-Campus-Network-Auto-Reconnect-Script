param([switch]$CheckOnly)
$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot
try {
    $nodeRoot = Join-Path $env:USERPROFILE '.cache\codex-runtimes\codex-primary-runtime\dependencies\node'
    $node = Join-Path $nodeRoot 'bin\node.exe'
    $module = Join-Path $nodeRoot 'node_modules\playwright\index.js'
    if (-not (Test-Path -LiteralPath $node) -or -not (Test-Path -LiteralPath $module)) { throw 'Codex Node/Playwright runtime missing. Please report this message.' }
    @{node=$node; playwright=$module} | ConvertTo-Json | Set-Content -LiteralPath runtime.json -Encoding utf8
    & $node (Join-Path $PSScriptRoot 'reconnect.cjs') --check
    if ($LASTEXITCODE -ne 0) { throw 'Runtime check failed. Keep Windows security enabled and report the output.' }
    if ($CheckOnly) { exit 0 }
    $account = (Read-Host 'Campus account').Trim()
    if ([string]::IsNullOrWhiteSpace($account)) { throw 'Account must not be empty.' }
    $secure = Read-Host 'Campus password (hidden)' -AsSecureString
    if ($secure.Length -eq 0) { throw 'Password must not be empty.' }
    (New-Object System.Management.Automation.PSCredential($account,$secure)) | Export-Clixml -LiteralPath credentials.xml
    Write-Host 'Account and encrypted password saved for this Windows user.'
    $action = New-ScheduledTaskAction -Execute $node -Argument ('"' + (Join-Path $PSScriptRoot 'reconnect.cjs') + '"') -WorkingDirectory $PSScriptRoot
    $trigger = New-ScheduledTaskTrigger -Daily -At '06:00'
    $principal = New-ScheduledTaskPrincipal -UserId ([System.Security.Principal.WindowsIdentity]::GetCurrent().Name) -LogonType Interactive -RunLevel Limited
    $settings = New-ScheduledTaskSettingsSet -WakeToRun -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Hours 1)
    Register-ScheduledTask -TaskName 'AHAU-Campus-Reconnect' -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
    Write-Host 'Installed: daily 06:00 local Windows time. Run test.cmd.'
} catch { Write-Host $_.Exception.Message -ForegroundColor Red; exit 1 }


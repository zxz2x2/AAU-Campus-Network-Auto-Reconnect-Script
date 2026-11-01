param([switch]$CheckOnly)
$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot
try {
    $nodeCommand = Get-Command node.exe -ErrorAction SilentlyContinue
    $npmCommand = Get-Command npm.cmd -ErrorAction SilentlyContinue
    if (-not $nodeCommand -or -not $npmCommand) { throw 'Install official Node.js LTS (with npm), then reopen install.cmd.' }
    $node = $nodeCommand.Source
    & $node -e 'if(Number(process.versions.node.split(String.fromCharCode(46))[0])<22)process.exit(1)'
    if ($LASTEXITCODE -ne 0) { throw 'Node.js 22 or newer is required.' }
    & $npmCommand.Source install --prefix $PSScriptRoot --no-audit --no-fund playwright-core
    if ($LASTEXITCODE -ne 0) { throw 'Dependency download failed. Connect to the Internet and try again.' }
    $module = Join-Path $PSScriptRoot 'node_modules\playwright-core\index.js'
    @{node=$node; playwright=$module} | ConvertTo-Json | Set-Content -LiteralPath runtime.json -Encoding utf8
    & $node (Join-Path $PSScriptRoot 'reconnect.cjs') --check
    if ($LASTEXITCODE -ne 0) { throw 'Runtime check failed. Keep Windows security enabled and report the output.' }
    if ($CheckOnly) { exit 0 }
    $portalText = (Read-Host 'School login URL (http:// or https://)').Trim()
    $portal = $null
    if (-not [Uri]::TryCreate($portalText,[UriKind]::Absolute,[ref]$portal) -or $portal.Scheme -notin @('http','https') -or $portal.UserInfo) { throw 'Invalid portal URL.' }
    $at = (Read-Host 'Daily login time HH:mm [06:00]').Trim()
    if (-not $at) { $at='06:00' }
    if ($at -notmatch '^(?:[01][0-9]|2[0-3]):[0-5][0-9]$') { throw 'Invalid time.' }
    $hosts = @($portal.DnsSafeHost)
    $extra = Read-Host 'Additional trusted authentication hostnames, comma-separated (Enter for none)'
    foreach ($h in ($extra -split ',')) {
        if ($h.Trim()) {
            $hostname=$h.Trim().ToLowerInvariant()
            if ([Uri]::CheckHostName($hostname) -eq [UriHostNameType]::Unknown) { throw 'Invalid hostname.' }
            $hosts += $hostname
        }
    }
    @{portalUrl=$portal.AbsoluteUri; allowedHosts=$hosts; usernameSelector=''; passwordSelector=''; submitSelector=''; beforeSubmit=@(); blockedHours=$null; maxAttempts=3; retrySeconds=60} | ConvertTo-Json -Depth 5 | Set-Content school.json -Encoding utf8
    $account = (Read-Host 'Campus account').Trim()
    if ([string]::IsNullOrWhiteSpace($account)) { throw 'Account must not be empty.' }
    $secure = Read-Host 'Campus password (hidden)' -AsSecureString
    if ($secure.Length -eq 0) { throw 'Password must not be empty.' }
    (New-Object System.Management.Automation.PSCredential($account,$secure)) | Export-Clixml -LiteralPath credentials.xml
    Write-Host 'Account and encrypted password saved for this Windows user.'
    $action = New-ScheduledTaskAction -Execute $node -Argument ('"' + (Join-Path $PSScriptRoot 'reconnect.cjs') + '"') -WorkingDirectory $PSScriptRoot
    $trigger = New-ScheduledTaskTrigger -Daily -At $at
    $principal = New-ScheduledTaskPrincipal -UserId ([System.Security.Principal.WindowsIdentity]::GetCurrent().Name) -LogonType Interactive -RunLevel Limited
    $settings = New-ScheduledTaskSettingsSet -WakeToRun -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Hours 1)
    Register-ScheduledTask -TaskName 'Campus-AutoReconnect' -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
    Write-Host ('Installed: daily '+$at+' local Windows time. Run test.cmd.')
} catch { Write-Host $_.Exception.Message -ForegroundColor Red; exit 1 }


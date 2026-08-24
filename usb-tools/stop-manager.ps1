param(
    [string]$AppRoot
)

$ErrorActionPreference = 'SilentlyContinue'

if (-not $AppRoot) {
    $ToolsDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    $AppRoot = Split-Path -Parent $ToolsDir
}

$StatusUrl = 'http://127.0.0.1:3077/api/status'
$ShutdownUrl = 'http://127.0.0.1:3077/api/shutdown'
$PidFile = Join-Path $AppRoot 'manager.pid'

function Test-ManagerOnline {
    try {
        $r = Invoke-WebRequest -Uri $StatusUrl -UseBasicParsing -TimeoutSec 1
        return $r.StatusCode -eq 200
    }
    catch {
        return $false
    }
}

if (Test-ManagerOnline) {
    try {
        Invoke-RestMethod `
            -Uri $ShutdownUrl `
            -Method Post `
            -Headers @{ 'X-Manager-Control' = '1' } `
            -TimeoutSec 2 | Out-Null
    }
    catch {}

    $deadline = (Get-Date).AddSeconds(5)
    do {
        Start-Sleep -Milliseconds 250
        if (-not (Test-ManagerOnline)) {
            exit 0
        }
    } while ((Get-Date) -lt $deadline)
}

if (Test-Path -LiteralPath $PidFile) {
    $pidText = (Get-Content -LiteralPath $PidFile -Raw).Trim()
    if ($pidText -match '^\d+$') {
        $targetPid = [int]$pidText
        $proc = Get-CimInstance Win32_Process -Filter "ProcessId=$targetPid"
        if ($proc) {
            $cmd = [string]$proc.CommandLine
            if ($cmd -match [regex]::Escape($AppRoot) -and $cmd -match 'manager\.js') {
                Stop-Process -Id $targetPid -Force -ErrorAction SilentlyContinue
                Start-Sleep -Milliseconds 500
            }
        }
    }
}

Remove-Item -LiteralPath $PidFile -Force -ErrorAction SilentlyContinue
exit 0

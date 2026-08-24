param(
    [switch]$NoBrowser
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms

$ToolsDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$AppRoot = Split-Path -Parent $ToolsDir
$NodeExe = Join-Path $AppRoot 'runtime\node.exe'
$ManagerJs = Join-Path $AppRoot 'manager.js'
$StatusUrl = 'http://127.0.0.1:3077/api/status'

function Test-ManagerOnline {
    try {
        $r = Invoke-WebRequest -Uri $StatusUrl -UseBasicParsing -TimeoutSec 1
        return $r.StatusCode -eq 200
    }
    catch {
        return $false
    }
}

if (-not (Test-Path -LiteralPath $NodeExe)) {
    [System.Windows.Forms.MessageBox]::Show(
        "Bundled Node runtime was not found:`n$NodeExe",
        'Minecraft ALT Manager',
        'OK',
        'Error'
    ) | Out-Null
    exit 1
}

if (-not (Test-Path -LiteralPath $ManagerJs)) {
    [System.Windows.Forms.MessageBox]::Show(
        "manager.js was not found:`n$ManagerJs",
        'Minecraft ALT Manager',
        'OK',
        'Error'
    ) | Out-Null
    exit 1
}

if (Test-ManagerOnline) {
    if (-not $NoBrowser) {
        Start-Process 'http://127.0.0.1:3077'
    }
    exit 0
}

$env:MAM_MODE = 'installed'
Remove-Item Env:MAM_PROFILE_DATA_DIR -ErrorAction SilentlyContinue
Remove-Item Env:MAM_SECRETS_DIR -ErrorAction SilentlyContinue
Remove-Item Env:MAM_AUTH_DATA_DIR -ErrorAction SilentlyContinue

Start-Process `
    -FilePath $NodeExe `
    -ArgumentList @("`"$ManagerJs`"") `
    -WorkingDirectory $AppRoot `
    -WindowStyle Hidden

$deadline = (Get-Date).AddSeconds(20)
do {
    Start-Sleep -Milliseconds 350
    if (Test-ManagerOnline) {
        if (-not $NoBrowser) {
            Start-Process 'http://127.0.0.1:3077'
        }
        exit 0
    }
} while ((Get-Date) -lt $deadline)

Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.MessageBox]::Show(
    "Minecraft ALT Manager did not become available on port 3077.`n`nTry STOP-MANAGER.cmd and start it again.",
    'Minecraft ALT Manager',
    'OK',
    'Error'
) | Out-Null
exit 2

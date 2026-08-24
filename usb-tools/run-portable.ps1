$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms

$ToolsDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$PackageRoot = Split-Path -Parent $ToolsDir
$AppRoot = Join-Path $PackageRoot 'app'
$NodeExe = Join-Path $AppRoot 'runtime\node.exe'
$ManagerJs = Join-Path $AppRoot 'manager.js'
$PortableIdFile = Join-Path $PackageRoot 'portable.id'
$StatusUrl = 'http://127.0.0.1:3077/api/status'

function Show-Error([string]$text) {
    [System.Windows.Forms.MessageBox]::Show($text, 'Minecraft ALT Manager', 'OK', 'Error') | Out-Null
}

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
    Show-Error "Bundled Node runtime is missing.`n`nRebuild the USB package."
    exit 1
}

if (-not (Test-Path -LiteralPath $PortableIdFile)) {
    Show-Error 'portable.id is missing. Rebuild the USB package.'
    exit 1
}

if (Test-ManagerOnline) {
    $pidFile = Join-Path $AppRoot 'manager.pid'
    $belongsToThisUsb = $false
    if (Test-Path -LiteralPath $pidFile) {
        $pidText = (Get-Content -LiteralPath $pidFile -Raw).Trim()
        if ($pidText -match '^\d+$') {
            $proc = Get-CimInstance Win32_Process -Filter "ProcessId=$pidText" -ErrorAction SilentlyContinue
            if ($proc -and ([string]$proc.CommandLine) -match [regex]::Escape($AppRoot)) {
                $belongsToThisUsb = $true
            }
        }
    }

    if ($belongsToThisUsb) {
        Start-Process 'http://127.0.0.1:3077'
        exit 0
    }

    Show-Error "Port 3077 is already used by another Minecraft ALT Manager instance.`n`nStop that Manager before starting Portable Mode."
    exit 2
}

$portableId = (Get-Content -LiteralPath $PortableIdFile -Raw).Trim()
if (-not $portableId) {
    Show-Error 'portable.id is empty. Rebuild the USB package.'
    exit 1
}

$LocalBase = Join-Path $env:LOCALAPPDATA 'QvarcY\MinecraftAltManager\PortableData'
$MachinePrivate = Join-Path $LocalBase $portableId
$SecretsDir = Join-Path $MachinePrivate 'secrets'
$AuthDir = Join-Path $MachinePrivate 'microsoft-auth'

New-Item -ItemType Directory -Path $SecretsDir -Force | Out-Null
New-Item -ItemType Directory -Path $AuthDir -Force | Out-Null

$env:MAM_MODE = 'portable'
$env:MAM_PROFILE_DATA_DIR = Join-Path $AppRoot 'data'
$env:MAM_SECRETS_DIR = $SecretsDir
$env:MAM_AUTH_DATA_DIR = $AuthDir

Start-Process `
    -FilePath $NodeExe `
    -ArgumentList @("`"$ManagerJs`"") `
    -WorkingDirectory $AppRoot `
    -WindowStyle Hidden

$deadline = (Get-Date).AddSeconds(20)
do {
    Start-Sleep -Milliseconds 350
    if (Test-ManagerOnline) {
        Start-Process 'http://127.0.0.1:3077'
        exit 0
    }
} while ((Get-Date) -lt $deadline)

Show-Error "Portable Manager did not become available on port 3077.`n`nIf a stale process exists, stop it and try again."
exit 3

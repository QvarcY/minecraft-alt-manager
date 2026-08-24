param(
    [string]$InstallDir
)

$ErrorActionPreference = 'SilentlyContinue'
Add-Type -AssemblyName System.Windows.Forms

$AppName = 'Minecraft ALT Manager'
$RegistryPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\MinecraftAltManager_QvarcY'
$LogFile = Join-Path $env:TEMP 'mam-uninstall-last.log'

if (-not $InstallDir) {
    $InstallDir = Join-Path $env:LOCALAPPDATA 'QvarcY\MinecraftAltManager'
}
$InstallDir = $InstallDir.TrimEnd('\')
$InstallMarker = Join-Path $InstallDir '.mam-installed.json'
$PortableDataDir = Join-Path $InstallDir 'PortableData'
$ParentDir = Split-Path -Parent $InstallDir

function Log([string]$Text) {
    $line = '[{0}] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Text
    Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8
}

function Test-InstalledManager {
    if (Test-Path -LiteralPath $InstallMarker) { return $true }
    $managerFile = Join-Path $InstallDir 'manager.js'
    $runtimeFile = Join-Path $InstallDir 'runtime\node.exe'
    return ((Test-Path -LiteralPath $managerFile) -and (Test-Path -LiteralPath $runtimeFile))
}

function Remove-InstallerRegistration {
    $desktop = [Environment]::GetFolderPath('Desktop')
    $startup = [Environment]::GetFolderPath('Startup')
    $startMenuDir = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\QvarcY\Minecraft ALT Manager'

    Remove-Item -LiteralPath (Join-Path $desktop "$AppName.lnk") -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath (Join-Path $startup "$AppName.lnk") -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $startMenuDir -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $RegistryPath -Recurse -Force -ErrorAction SilentlyContinue
}

function Stop-InstalledManager {
    $stopScript = Join-Path $InstallDir 'tools\stop-manager.ps1'
    if (Test-Path -LiteralPath $stopScript) {
        try {
            Log 'Calling installed stop-manager.ps1.'
            & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $stopScript -AppRoot $InstallDir | Out-Null
        } catch {
            Log ('stop-manager.ps1 failed: ' + $_.Exception.Message)
        }
    }

    $deadline = (Get-Date).AddSeconds(8)
    do {
        $listener = Get-NetTCPConnection -LocalPort 3077 -State Listen -ErrorAction SilentlyContinue
        if (-not $listener) { return }
        Start-Sleep -Milliseconds 350
    } while ((Get-Date) -lt $deadline)

    # Fallback: only terminate the PID recorded by THIS installed copy and only if
    # its command line points back to this install directory. Never kill all node.exe.
    $pidFile = Join-Path $InstallDir 'manager.pid'
    if (Test-Path -LiteralPath $pidFile) {
        $pidText = (Get-Content -LiteralPath $pidFile -Raw -ErrorAction SilentlyContinue).Trim()
        if ($pidText -match '^\d+$') {
            $proc = Get-CimInstance Win32_Process -Filter "ProcessId=$pidText" -ErrorAction SilentlyContinue
            if ($proc -and ([string]$proc.CommandLine) -match [regex]::Escape($InstallDir)) {
                Log ("Stopping remaining installed Manager PID $pidText.")
                Stop-Process -Id ([int]$pidText) -Force -ErrorAction SilentlyContinue
                Start-Sleep -Milliseconds 500
            }
        }
    }
}

function Remove-InstalledContent {
    $deadline = (Get-Date).AddSeconds(30)
    $attempt = 0

    do {
        $attempt++
        if (-not (Test-Path -LiteralPath $InstallDir)) { return @() }

        $items = @(Get-ChildItem -LiteralPath $InstallDir -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -ne 'PortableData' })

        if ($items.Count -eq 0) { return @() }
        Log ("Cleanup attempt {0}: {1} installed item(s) remain." -f $attempt, $items.Count)

        foreach ($item in $items) {
            try {
                Remove-Item -LiteralPath $item.FullName -Recurse -Force -ErrorAction Stop
                Log ('Removed: ' + $item.Name)
            }
            catch {
                Log ('Still locked/failed: ' + $item.Name + ' | ' + $_.Exception.Message)
            }
        }

        Start-Sleep -Seconds 1
    } while ((Get-Date) -lt $deadline)

    if (-not (Test-Path -LiteralPath $InstallDir)) { return @() }
    return @(Get-ChildItem -LiteralPath $InstallDir -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -ne 'PortableData' })
}

Set-Content -LiteralPath $LogFile -Value ("Minecraft ALT Manager uninstall v1.4 cleanup`r`nInstallDir: " + $InstallDir) -Encoding UTF8
Log ('Uninstaller started from: ' + $PSCommandPath)

if (-not (Test-Path -LiteralPath $InstallDir) -or -not (Test-InstalledManager)) {
    Remove-InstallerRegistration
    Log 'No installed Manager detected. Registration cleanup only.'
    $portableNote = if (Test-Path -LiteralPath $PortableDataDir) {
        "`n`nPortable Mode private data exists and was left untouched."
    } else { '' }
    [System.Windows.Forms.MessageBox]::Show(
        "$AppName is not installed in:`n$InstallDir$portableNote",
        $AppName,
        'OK',
        'Information'
    ) | Out-Null
    Remove-Item -LiteralPath $LogFile -Force -ErrorAction SilentlyContinue
    exit 0
}

$result = [System.Windows.Forms.MessageBox]::Show(
    "Uninstall $AppName from this PC?`n`nThis removes the installed application, installed profiles/settings, installed DPAPI passwords, Microsoft login cache, shortcuts and the uninstall registry entry.`n`nPortable Mode data belonging to USB packages is preserved. Use CLEAN-PORTABLE-DATA.cmd on the relevant USB if you want to remove that separately.",
    "Uninstall $AppName",
    'YesNo',
    'Warning'
)

if ($result -ne 'Yes') {
    Log 'Uninstall cancelled by user.'
    Remove-Item -LiteralPath $LogFile -Force -ErrorAction SilentlyContinue
    exit 0
}

Log 'Uninstall confirmed.'
Stop-InstalledManager
Remove-InstallerRegistration
Log 'Shortcuts and uninstall registration removed.'

$remaining = @(Remove-InstalledContent)

if ($remaining.Count -eq 0) {
    Log 'All installed application content removed.'

    if (Test-Path -LiteralPath $PortableDataDir) {
        Log 'PortableData preserved.'
    }
    elseif (Test-Path -LiteralPath $InstallDir) {
        $left = @(Get-ChildItem -LiteralPath $InstallDir -Force -ErrorAction SilentlyContinue)
        if ($left.Count -eq 0) {
            Remove-Item -LiteralPath $InstallDir -Force -ErrorAction SilentlyContinue
            Log 'Empty install directory removed.'
        }
    }

    if (Test-Path -LiteralPath $ParentDir) {
        $parentItems = @(Get-ChildItem -LiteralPath $ParentDir -Force -ErrorAction SilentlyContinue)
        if ($parentItems.Count -eq 0) {
            Remove-Item -LiteralPath $ParentDir -Force -ErrorAction SilentlyContinue
        }
    }

    $portableNote = if (Test-Path -LiteralPath $PortableDataDir) {
        "`n`nPortable Mode private data was preserved."
    } else { '' }

    [System.Windows.Forms.MessageBox]::Show(
        "$AppName has been uninstalled successfully.$portableNote",
        $AppName,
        'OK',
        'Information'
    ) | Out-Null

    # Successful uninstall should not leave our own diagnostic log behind.
    Remove-Item -LiteralPath $LogFile -Force -ErrorAction SilentlyContinue

    # If this script was launched from a temporary copy, remove that copy too.
    $tempRoot = [IO.Path]::GetFullPath($env:TEMP).TrimEnd('\') + '\'
    $selfPath = [IO.Path]::GetFullPath($PSCommandPath)
    if ($selfPath.StartsWith($tempRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item -LiteralPath $PSCommandPath -Force -ErrorAction SilentlyContinue
    }
    exit 0
}

$remainingNames = ($remaining | ForEach-Object { $_.Name }) -join ', '
Log ('ERROR: cleanup incomplete. Remaining installed items: ' + $remainingNames)
[System.Windows.Forms.MessageBox]::Show(
    "$AppName uninstall cleanup could not remove all installed files.`n`nRemaining: $remainingNames`n`nDiagnostic log:`n$LogFile",
    $AppName,
    'OK',
    'Error'
) | Out-Null
exit 2

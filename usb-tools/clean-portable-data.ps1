$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms

$ToolsDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$PackageRoot = Split-Path -Parent $ToolsDir
$PortableIdFile = Join-Path $PackageRoot 'portable.id'

if (-not (Test-Path -LiteralPath $PortableIdFile)) {
    [System.Windows.Forms.MessageBox]::Show('portable.id was not found.', 'Minecraft ALT Manager', 'OK', 'Error') | Out-Null
    exit 1
}

$portableId = (Get-Content -LiteralPath $PortableIdFile -Raw).Trim()
$MachinePrivate = Join-Path $env:LOCALAPPDATA "QvarcY\MinecraftAltManager\PortableData\$portableId"

$result = [System.Windows.Forms.MessageBox]::Show(
    "Remove this USB Manager's local private data from this PC?`n`nThis deletes saved DPAPI passwords and Microsoft login cache for Portable Mode.`nProfiles stored on the USB will NOT be deleted.",
    'Clean Portable Data',
    'YesNo',
    'Warning'
)

if ($result -ne 'Yes') { exit 0 }

if (Test-Path -LiteralPath $MachinePrivate) {
    Remove-Item -LiteralPath $MachinePrivate -Recurse -Force
}

[System.Windows.Forms.MessageBox]::Show(
    'Portable private data was removed from this PC.',
    'Minecraft ALT Manager',
    'OK',
    'Information'
) | Out-Null

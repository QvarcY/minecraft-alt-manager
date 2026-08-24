param(
    [Parameter(Position = 0)]
    [string]$Version
)

$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$MetaFile = Join-Path $ProjectRoot 'core\app-meta.js'
$PackageFile = Join-Path $ProjectRoot 'package.json'
$LockFile = Join-Path $ProjectRoot 'package-lock.json'

if (-not $Version) {
    $Version = Read-Host 'New application version (example: 3.1.2)'
}
$Version = $Version.Trim()

if ($Version -notmatch '^\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?$') {
    throw "Invalid version '$Version'. Use SemVer format such as 3.1.2 or 3.2.0-beta.1."
}

if (-not (Test-Path -LiteralPath $MetaFile)) {
    throw "Missing metadata file: $MetaFile"
}
if (-not (Test-Path -LiteralPath $PackageFile)) {
    throw "Missing package.json: $PackageFile"
}

$node = (Get-Command node.exe -ErrorAction Stop).Source
$metaProbe = 'const m=require(process.argv[1]); process.stdout.write(JSON.stringify(m));'
$currentJson = & $node -e $metaProbe $MetaFile
if ($LASTEXITCODE -ne 0 -or -not $currentJson) {
    throw 'Could not read current app metadata.'
}
$currentMeta = $currentJson | ConvertFrom-Json
$OldVersion = [string]$currentMeta.version

$archiveDir = Join-Path $ProjectRoot ("_ARCHIVE\version-change-" + (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'))
New-Item -ItemType Directory -Path $archiveDir -Force | Out-Null
Copy-Item -LiteralPath $MetaFile -Destination $archiveDir -Force
Copy-Item -LiteralPath $PackageFile -Destination $archiveDir -Force
if (Test-Path -LiteralPath $LockFile) {
    Copy-Item -LiteralPath $LockFile -Destination $archiveDir -Force
}

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$metaText = [System.IO.File]::ReadAllText($MetaFile)
$pattern = "(?m)^(\s*version:\s*)'[^']+'(,?)\s*$"
$replacement = '${1}' + "'$Version'" + '${2}'
$updatedMeta = [regex]::Replace($metaText, $pattern, $replacement)
if ($updatedMeta -eq $metaText -and $OldVersion -ne $Version) {
    throw 'Could not find the version field in core\app-meta.js.'
}
[System.IO.File]::WriteAllText($MetaFile, $updatedMeta, $utf8NoBom)

$syncScript = @'
const fs = require('fs')
const path = require('path')
const root = process.argv[1]
const version = process.argv[2]
const meta = require(path.join(root, 'core', 'app-meta.js'))
const packagePath = path.join(root, 'package.json')
const lockPath = path.join(root, 'package-lock.json')

const pkg = JSON.parse(fs.readFileSync(packagePath, 'utf8').replace(/^\uFEFF/, ''))
pkg.name = 'minecraft-alt-manager'
pkg.version = version
pkg.description = 'Universal Minecraft ALT profile and automation manager'
pkg.main = 'manager.js'
pkg.author = `${meta.author} <${meta.website}>`
pkg.license = 'GPL-3.0-only'
pkg.private = true
pkg.type = 'commonjs'
pkg.scripts = {
  ...(pkg.scripts || {}),
  start: 'node manager.js',
  check: 'node --check manager.js'
}
delete pkg.scripts.test
fs.writeFileSync(packagePath, JSON.stringify(pkg, null, 2) + '\n', 'utf8')

if (fs.existsSync(lockPath)) {
  const lock = JSON.parse(fs.readFileSync(lockPath, 'utf8').replace(/^\uFEFF/, ''))
  lock.name = pkg.name
  lock.version = version
  if (lock.packages && lock.packages['']) {
    lock.packages[''].name = pkg.name
    lock.packages[''].version = version
  }
  fs.writeFileSync(lockPath, JSON.stringify(lock, null, 2) + '\n', 'utf8')
}
'@

& $node -e $syncScript $ProjectRoot $Version
if ($LASTEXITCODE -ne 0) {
    throw 'Failed to synchronize package metadata.'
}

$newJson = & $node -e $metaProbe $MetaFile
$newMeta = $newJson | ConvertFrom-Json
if ([string]$newMeta.version -ne $Version) {
    throw 'Version verification failed after update.'
}

Write-Host ''
Write-Host '===============================================' -ForegroundColor Green
Write-Host ' APPLICATION VERSION UPDATED' -ForegroundColor Green
Write-Host '===============================================' -ForegroundColor Green
Write-Host "Old version: $OldVersion"
Write-Host "New version: $Version"
Write-Host "Backup:      $archiveDir"
Write-Host ''
Write-Host 'Updated:'
Write-Host '  core\app-meta.js'
Write-Host '  package.json'
if (Test-Path -LiteralPath $LockFile) { Write-Host '  package-lock.json' }
Write-Host ''
Write-Host 'Next:'
Write-Host '  1. Test the application.'
Write-Host '  2. Run BUILD-USB.cmd.'
Write-Host '  3. Test RUN-PORTABLE.cmd from the new build.'
Write-Host ''

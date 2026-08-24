$ErrorActionPreference = 'Stop'

$BuilderVersion = '1.7.0'
$ReleaseStage = 'Stable'
$ProjectRoot = $PSScriptRoot
$BuildRoot = Join-Path $ProjectRoot 'PORTABLE-BUILD'
$TemplateRoot = Join-Path $ProjectRoot 'usb-tools'
$DocsRoot = Join-Path $ProjectRoot 'docs'
$MetaFile = Join-Path $ProjectRoot 'core\app-meta.js'
$StablePortableIdFile = Join-Path $ProjectRoot '.portable-id'
$UsbRoot = $null
$AppRoot = $null
$ToolsRoot = $null

function Write-Step([string]$Text) {
    Write-Host ''
    Write-Host "==> $Text" -ForegroundColor Cyan
}

function Write-Ok([string]$Text) {
    Write-Host "[OK] $Text" -ForegroundColor Green
}

function Copy-Tree([string]$Source, [string]$Destination) {
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    & robocopy $Source $Destination /E /R:2 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
    $code = $LASTEXITCODE
    if ($code -gt 7) {
        throw "ROBOCOPY failed for '$Source' (exit code $code)."
    }
}

function Get-TreeSize([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return 0 }
    return [int64]((Get-ChildItem -LiteralPath $Path -File -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum)
}

function Format-Mb([int64]$Bytes) {
    return ([math]::Round($Bytes / 1MB, 1)).ToString('0.0') + ' MB'
}

function Test-IsPackageRoot([string]$NodeModulesRoot, [string]$Directory) {
    $relative = $Directory.Substring($NodeModulesRoot.Length).TrimStart('\')
    if (-not $relative) { return $true }
    $parts = @($relative -split '\\')
    if ($parts.Count -eq 1) { return $true }
    if ($parts.Count -eq 2 -and $parts[0].StartsWith('@')) { return $true }
    return $false
}

function Optimize-NodeModules([string]$NodeModulesRoot) {
    $before = Get-TreeSize $NodeModulesRoot
    $removedFiles = 0
    $removedDirs = 0

    # Conservative release cleanup: only build-time/test/documentation artefacts.
    # We intentionally keep src/lib/dist/data/package.json and all licence/notice files.
    $dropDirNames = @(
        '.github', '.circleci', '.nyc_output',
        '__tests__', 'test', 'tests',
        'doc', 'docs', 'documentation',
        'example', 'examples', 'sample', 'samples',
        'benchmark', 'benchmarks', 'coverage'
    )

    $dirs = @(Get-ChildItem -LiteralPath $NodeModulesRoot -Directory -Recurse -Force -ErrorAction SilentlyContinue |
        Sort-Object { $_.FullName.Length } -Descending)
    foreach ($dir in $dirs) {
        if ($dropDirNames -notcontains $dir.Name.ToLowerInvariant()) { continue }
        if (Test-IsPackageRoot -NodeModulesRoot $NodeModulesRoot -Directory $dir.FullName) { continue }
        try {
            Remove-Item -LiteralPath $dir.FullName -Recurse -Force -ErrorAction Stop
            $removedDirs++
        } catch {}
    }

    $files = @(Get-ChildItem -LiteralPath $NodeModulesRoot -File -Recurse -Force -ErrorAction SilentlyContinue)
    foreach ($file in $files) {
        $name = $file.Name
        $lower = $name.ToLowerInvariant()
        $keepLegal = $lower -match '^(license|licence|notice|copying)(\.|$)'
        $drop = $false

        if ($lower.EndsWith('.map')) { $drop = $true }
        elseif ($lower.EndsWith('.d.ts')) { $drop = $true }
        elseif (($lower.EndsWith('.md') -or $lower.EndsWith('.markdown')) -and -not $keepLegal) { $drop = $true }
        elseif ($lower -in @('.eslintrc', '.eslintignore', '.prettierignore', '.npmignore', 'tsconfig.json', 'typedoc.json')) { $drop = $true }

        if ($drop) {
            try {
                Remove-Item -LiteralPath $file.FullName -Force -ErrorAction Stop
                $removedFiles++
            } catch {}
        }
    }

    $after = Get-TreeSize $NodeModulesRoot
    return [ordered]@{
        beforeBytes = $before
        afterBytes = $after
        savedBytes = [math]::Max(0, $before - $after)
        removedFiles = $removedFiles
        removedDirs = $removedDirs
    }
}


function Optimize-MinecraftDataForJava([string]$NodeModulesRoot) {
    $packageRoot = Join-Path $NodeModulesRoot 'minecraft-data'
    $dataRoot = Join-Path $packageRoot 'minecraft-data\data'
    $pcRoot = Join-Path $dataRoot 'pc'
    $bedrockRoot = Join-Path $dataRoot 'bedrock'
    $bedrockCommon = Join-Path $bedrockRoot 'common'

    if (-not (Test-Path -LiteralPath $packageRoot)) {
        throw 'minecraft-data package is missing from the release build.'
    }
    if (-not (Test-Path -LiteralPath $pcRoot)) {
        throw 'minecraft-data Java/PC data directory is missing.'
    }
    if (-not (Test-Path -LiteralPath $bedrockRoot)) {
        throw 'minecraft-data Bedrock data directory is missing; refusing to apply an unknown layout optimization.'
    }
    if (-not (Test-Path -LiteralPath $bedrockCommon)) {
        throw 'minecraft-data Bedrock common directory is missing; loader compatibility cannot be guaranteed.'
    }

    # node-minecraft-data loads these Bedrock common metadata files eagerly even for Java Edition.
    # Keep the complete tiny common directory, but remove the large version-specific Bedrock payload.
    foreach ($name in @('protocolVersions.json', 'versions.json', 'legacy.json')) {
        if (-not (Test-Path -LiteralPath (Join-Path $bedrockCommon $name))) {
            throw "minecraft-data required Bedrock common file is missing: $name"
        }
    }

    foreach ($name in @('protocolVersions.json', 'versions.json', 'legacy.json')) {
        $pcCommonFile = Join-Path $pcRoot "common\$name"
        if (-not (Test-Path -LiteralPath $pcCommonFile)) {
            throw "minecraft-data required Java common file is missing: $pcCommonFile"
        }
    }

    $before = Get-TreeSize $bedrockRoot
    $removedItems = 0

    Get-ChildItem -LiteralPath $bedrockRoot -Force -ErrorAction Stop | ForEach-Object {
        if ($_.Name -ine 'common') {
            Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction Stop
            $removedItems++
        }
    }

    $after = Get-TreeSize $bedrockRoot
    $remaining = @(Get-ChildItem -LiteralPath $bedrockRoot -Force -ErrorAction Stop | Where-Object { $_.Name -ine 'common' })
    if ($remaining.Count -gt 0) {
        throw 'Java-only minecraft-data optimization left unexpected Bedrock version data behind.'
    }

    return [ordered]@{
        beforeBytes = $before
        afterBytes = $after
        savedBytes = [math]::Max(0, $before - $after)
        removedItems = $removedItems
    }
}

function New-VerifiedReleaseArchive([string]$SourceDirectory, [string]$BuildDirectory, [string]$ReleaseFolderName, [string]$ArchiveFileName) {
    $archivePath = Join-Path $BuildDirectory $ArchiveFileName
    if (Test-Path -LiteralPath $archivePath) {
        Remove-Item -LiteralPath $archivePath -Force
    }

    $tar = Get-Command tar.exe -ErrorAction SilentlyContinue
    $createdWithTar = $false
    if ($tar) {
        Push-Location $BuildDirectory
        try {
            & $tar.Source -a -c -f $archivePath $ReleaseFolderName
            if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $archivePath)) {
                $createdWithTar = $true
            }
        }
        finally { Pop-Location }
    }

    if (-not $createdWithTar) {
        # Windows 10/11 normally ships tar.exe. Keep a .NET fallback for unusual systems.
        Remove-Item -LiteralPath $archivePath -Force -ErrorAction SilentlyContinue
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::CreateFromDirectory(
            $SourceDirectory,
            $archivePath,
            [System.IO.Compression.CompressionLevel]::Optimal,
            $true
        )
    }

    if (-not (Test-Path -LiteralPath $archivePath)) { throw 'Final ZIP creation failed.' }

    if ($createdWithTar) {
        $listing = @(& $tar.Source -tf $archivePath)
        if ($LASTEXITCODE -ne 0) { throw 'Unable to verify final ZIP contents with tar.exe.' }
        $entryNames = @($listing | ForEach-Object { ($_ -replace '\\','/').TrimEnd('/') })
    }
    else {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $zip = [System.IO.Compression.ZipFile]::OpenRead($archivePath)
        try {
            $entryNames = @($zip.Entries | ForEach-Object { $_.FullName.Replace('\\','/').TrimEnd('/') })
        }
        finally { $zip.Dispose() }
    }

    foreach ($requiredEntry in @(
        "$ReleaseFolderName/README-FIRST.txt",
        "$ReleaseFolderName/LIETOSANAS-PAMACIBA-LV.txt",
        "$ReleaseFolderName/USER-GUIDE-EN.txt",
        "$ReleaseFolderName/CHANGELOG.txt",
        "$ReleaseFolderName/app/manager.js"
    )) {
        if ($entryNames -notcontains $requiredEntry) {
            throw "Final ZIP verification failed; missing entry: $requiredEntry"
        }
    }

    $item = Get-Item -LiteralPath $archivePath
    if ($item.Length -le 0) { throw 'Final ZIP is empty.' }
    return $archivePath
}

function Get-Sha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Assert-FileMatch([string]$Source, [string]$Destination, [string]$Label) {
    if (-not (Test-Path -LiteralPath $Source)) {
        throw "Verification failed: source file missing: $Source"
    }
    if (-not (Test-Path -LiteralPath $Destination)) {
        throw "Verification failed: built file missing: $Destination"
    }

    $sourceHash = Get-Sha256 $Source
    $destHash = Get-Sha256 $Destination
    if ($sourceHash -ne $destHash) {
        throw "Verification failed: $Label hash mismatch."
    }

    Write-Ok "$Label hash MATCH"
}

function Assert-TreeMatch([string]$SourceRoot, [string]$DestinationRoot, [string]$Label) {
    $sourceFiles = @(Get-ChildItem -LiteralPath $SourceRoot -File -Recurse)
    foreach ($sourceFile in $sourceFiles) {
        $relative = $sourceFile.FullName.Substring($SourceRoot.Length).TrimStart('\')
        $destFile = Join-Path $DestinationRoot $relative
        if (-not (Test-Path -LiteralPath $destFile)) {
            throw "Verification failed: $Label file missing in build: $relative"
        }
        if ((Get-Sha256 $sourceFile.FullName) -ne (Get-Sha256 $destFile)) {
            throw "Verification failed: $Label hash mismatch: $relative"
        }
    }
    Write-Ok "$Label tree MATCH ($($sourceFiles.Count) files)"
}

function Read-AppMeta([string]$NodeExe, [string]$Path) {
    $probe = 'const m=require(process.argv[1]); process.stdout.write(JSON.stringify(m));'
    $json = & $NodeExe -e $probe $Path
    if ($LASTEXITCODE -ne 0 -or -not $json) {
        throw "Unable to read application metadata from $Path"
    }
    return ($json | ConvertFrom-Json)
}

function Sync-PackageMetadata([string]$NodeExe, [string]$Version, [string]$Author, [string]$Website) {
    $script = @'
const fs = require('fs')
const path = require('path')

const root = process.argv[1]
const version = process.argv[2]
const author = process.argv[3]
const website = process.argv[4]

const packagePath = path.join(root, 'package.json')
const lockPath = path.join(root, 'package-lock.json')

const pkg = JSON.parse(fs.readFileSync(packagePath, 'utf8').replace(/^\uFEFF/, ''))
pkg.name = 'minecraft-alt-manager'
pkg.version = version
pkg.description = 'Universal Minecraft ALT profile and automation manager'
pkg.main = 'manager.js'
pkg.author = `${author} <${website}>`
pkg.license = 'UNLICENSED'
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

    & $NodeExe -e $script $ProjectRoot $Version $Author $Website
    if ($LASTEXITCODE -ne 0) {
        throw 'Failed to synchronize package.json/package-lock.json metadata.'
    }
}

Write-Host '==============================================='
Write-Host " Minecraft ALT Manager USB Builder v$BuilderVersion"
Write-Host '==============================================='

Write-Step 'Checking project files'

$required = @(
    'manager.js',
    'package.json',
    'package-lock.json',
    'decrypt-password.ps1',
    'save-secret.ps1',
    'core',
    'core\app-meta.js',
    'web',
    'node_modules',
    'usb-tools',
    'usb-tools\INSTALL.cmd',
    'usb-tools\RUN-PORTABLE.cmd',
    'usb-tools\CLEAN-PORTABLE-DATA.cmd',
    'usb-tools\UNINSTALL-FROM-PC.cmd',
    'usb-tools\SELF-TEST.cmd',
    'usb-tools\installer.ps1',
    'usb-tools\start-manager.ps1',
    'usb-tools\stop-manager.ps1',
    'usb-tools\run-portable.ps1',
    'usb-tools\clean-portable-data.ps1',
    'usb-tools\uninstall-installed.ps1',
    'usb-tools\self-test.ps1',
    'docs\LIETOSANAS-PAMACIBA-LV.txt',
    'docs\USER-GUIDE-EN.txt',
    'docs\CHANGELOG.txt'
)

foreach ($item in $required) {
    $path = Join-Path $ProjectRoot $item
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Required project item is missing: $path"
    }
}

# Release-safety regression guard. A legacy installer once generated an in-place
# UNINSTALL.cmd using -InstallDir "%~dp0". Because %~dp0 ends with a backslash,
# Windows argument parsing can pass a literal trailing quote to PowerShell.
# It also did not create the installation marker. Refuse to build such a package.
$installerText = Get-Content -LiteralPath (Join-Path $ProjectRoot 'usb-tools\installer.ps1') -Raw
$uninstallerText = Get-Content -LiteralPath (Join-Path $ProjectRoot 'usb-tools\uninstall-installed.ps1') -Raw
$installerSafetyChecks = @(
    ($installerText -match '\.mam-installed\.json'),
    ($installerText -match 'mam-uninstall-'),
    ($installerText -match 'copy /Y .*uninstall-installed\.ps1'),
    ($installerText -match 'MAM_INSTALL'),
    ($installerText -match 'Set-Content.*UNINSTALL\.cmd')
)
if ($installerSafetyChecks -contains $false) {
    throw 'Unsafe/legacy installer.ps1 detected. Restore the Distribution Safety installer before building.'
}
$uninstallerSafetyChecks = @(
    ($uninstallerText -match 'PortableData'),
    ($uninstallerText -match 'Remove-InstalledContent'),
    ($uninstallerText -match 'manager\.js'),
    ($uninstallerText -match 'runtime\\node\.exe'),
    ($uninstallerText -match 'mam-uninstall-last\.log')
)
if ($uninstallerSafetyChecks -contains $false) {
    throw 'Unexpected uninstall-installed.ps1 detected. Release cleanup safety checks failed.'
}
Write-Ok 'Installer/uninstaller safety architecture verified'

$nodeCommand = Get-Command node.exe -ErrorAction Stop
$NodeExe = $nodeCommand.Source
Write-Host "Node runtime: $NodeExe"

$AppMeta = Read-AppMeta -NodeExe $NodeExe -Path $MetaFile
$AppName = [string]$AppMeta.name
$Version = [string]$AppMeta.version
$Author = [string]$AppMeta.author
$Website = [string]$AppMeta.website
$Tagline = [string]$AppMeta.tagline

if (-not $AppName -or -not $Version -or -not $Author -or -not $Website -or -not $Tagline) {
    throw 'core\app-meta.js is missing one or more required metadata fields.'
}
if ($Version -notmatch '^\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?$') {
    throw "Invalid application version in core\app-meta.js: $Version"
}

$ArchitectureLabel = if ($env:PROCESSOR_ARCHITECTURE -match '64') { 'x64' } else { 'x86' }
$ReleaseAuthor = ($Author -replace '[^0-9A-Za-z._-]', '_')
$ReleaseName = "MinecraftAltManager_By_$ReleaseAuthor-v$Version-Windows-$ArchitectureLabel"
$ArchiveName = "$ReleaseName.zip"
$UsbRoot = Join-Path $BuildRoot $ReleaseName
$AppRoot = Join-Path $UsbRoot 'app'
$ToolsRoot = Join-Path $UsbRoot 'tools'

Write-Host "Application: $AppName v$Version"
Write-Host "Release:     $ReleaseName"
Write-Host "$Tagline | $Website"

Write-Step 'Synchronizing package metadata'
Sync-PackageMetadata -NodeExe $NodeExe -Version $Version -Author $Author -Website $Website
Write-Ok "package.json/package-lock.json synchronized to v$Version"

$physicsFile = Join-Path $ProjectRoot 'node_modules\mineflayer\lib\plugins\physics.js'
if (-not (Test-Path -LiteralPath $physicsFile)) {
    throw 'Mineflayer physics.js was not found.'
}
$physicsText = Get-Content -LiteralPath $physicsFile -Raw
if ($physicsText -notmatch "write\('tick_end'" -and $physicsText -notmatch 'write\("tick_end"') {
    throw 'The installed Mineflayer does not contain the required client tick_end patch.'
}
Write-Ok 'Mineflayer tick_end patch present in source'

Write-Step 'Checking JavaScript syntax'
$jsFiles = @(
    (Join-Path $ProjectRoot 'manager.js'),
    (Join-Path $ProjectRoot 'web\app.js')
)
$jsFiles += Get-ChildItem -LiteralPath (Join-Path $ProjectRoot 'core') -Filter '*.js' -File | Select-Object -ExpandProperty FullName
foreach ($file in $jsFiles) {
    & $NodeExe --check $file
    if ($LASTEXITCODE -ne 0) {
        throw "JavaScript syntax check failed: $file"
    }
}
Write-Ok 'JavaScript syntax OK'

# Portable identity survives application updates. The project-level .portable-id
# is never recreated during a normal release build.
function Read-ValidPortableId([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $value = (Get-Content -LiteralPath $Path -Raw -ErrorAction SilentlyContinue).Trim()
    if ($value -match '^[0-9a-fA-F]{32}$') { return $value.ToLowerInvariant() }
    return $null
}

$portableId = Read-ValidPortableId $StablePortableIdFile
if (-not $portableId) {
    $portableId = [guid]::NewGuid().ToString('N')
    Set-Content -LiteralPath $StablePortableIdFile -Value $portableId -Encoding ASCII -NoNewline
    Write-Ok "Created stable Portable ID ($portableId)"
}
else {
    Write-Ok "Stable Portable ID loaded ($portableId)"
}

Write-Step 'Creating clean USB build'
if (Test-Path -LiteralPath $BuildRoot) {
    Remove-Item -LiteralPath $BuildRoot -Recurse -Force
}
New-Item -ItemType Directory -Path $AppRoot -Force | Out-Null
New-Item -ItemType Directory -Path $ToolsRoot -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $AppRoot 'runtime') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $AppRoot 'data\profiles') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $AppRoot 'data\secrets') -Force | Out-Null

Write-Step 'Copying Manager application'
Copy-Item -LiteralPath (Join-Path $ProjectRoot 'manager.js') -Destination $AppRoot -Force
Copy-Item -LiteralPath (Join-Path $ProjectRoot 'package.json') -Destination $AppRoot -Force
Copy-Item -LiteralPath (Join-Path $ProjectRoot 'decrypt-password.ps1') -Destination $AppRoot -Force
Copy-Item -LiteralPath (Join-Path $ProjectRoot 'save-secret.ps1') -Destination $AppRoot -Force
Copy-Tree -Source (Join-Path $ProjectRoot 'core') -Destination (Join-Path $AppRoot 'core')
Copy-Tree -Source (Join-Path $ProjectRoot 'web') -Destination (Join-Path $AppRoot 'web')

Write-Step 'Copying dependencies (this can take a while)'
Copy-Tree -Source (Join-Path $ProjectRoot 'node_modules') -Destination (Join-Path $AppRoot 'node_modules')

Write-Step 'Optimizing release dependencies (build copy only)'
$optimization = Optimize-NodeModules -NodeModulesRoot (Join-Path $AppRoot 'node_modules')
Write-Ok ("Dependencies: {0} -> {1}; saved {2}; removed {3} files / {4} folders" -f `
    (Format-Mb $optimization.beforeBytes), `
    (Format-Mb $optimization.afterBytes), `
    (Format-Mb $optimization.savedBytes), `
    $optimization.removedFiles, `
    $optimization.removedDirs)

Write-Step 'Optimizing minecraft-data for Java Edition (build copy only)'
$javaDataOptimization = Optimize-MinecraftDataForJava -NodeModulesRoot (Join-Path $AppRoot 'node_modules')
Write-Ok ("Bedrock payload: {0} -> {1}; saved {2}; removed {3} version item(s); common metadata preserved" -f `
    (Format-Mb $javaDataOptimization.beforeBytes), `
    (Format-Mb $javaDataOptimization.afterBytes), `
    (Format-Mb $javaDataOptimization.savedBytes), `
    $javaDataOptimization.removedItems)

Write-Step 'Copying bundled Node runtime'
Copy-Item -LiteralPath $NodeExe -Destination (Join-Path $AppRoot 'runtime\node.exe') -Force

Write-Step 'Copying portable profiles (passwords are excluded)'
$sourceProfiles = Join-Path $ProjectRoot 'data\profiles'
if (Test-Path -LiteralPath $sourceProfiles) {
    Get-ChildItem -LiteralPath $sourceProfiles -Filter '*.json' -File | ForEach-Object {
        # Validate profile JSON before packaging.
        try {
            Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json | Out-Null
        }
        catch {
            throw "Invalid profile JSON: $($_.FullName)"
        }
        Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $AppRoot 'data\profiles') -Force
        Write-Host "Profile included: $($_.Name)"
    }
}

$sourceSettings = Join-Path $ProjectRoot 'data\settings.json'
if (Test-Path -LiteralPath $sourceSettings) {
    try {
        Get-Content -LiteralPath $sourceSettings -Raw | ConvertFrom-Json | Out-Null
    }
    catch {
        throw "Invalid settings JSON: $sourceSettings"
    }
    Copy-Item -LiteralPath $sourceSettings -Destination (Join-Path $AppRoot 'data\settings.json') -Force
}

# Never copy DPAPI passwords, legacy secrets or Microsoft auth caches.
Remove-Item -LiteralPath (Join-Path $AppRoot 'secret.dat') -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath (Join-Path $AppRoot 'data\microsoft-auth') -Recurse -Force -ErrorAction SilentlyContinue
Get-ChildItem -LiteralPath (Join-Path $AppRoot 'data\secrets') -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

Write-Step 'Adding USB launchers, installer and uninstaller'
$rootTemplates = @(
    'INSTALL.cmd',
    'RUN-PORTABLE.cmd',
    'CLEAN-PORTABLE-DATA.cmd',
    'UNINSTALL-FROM-PC.cmd',
    'SELF-TEST.cmd'
)
foreach ($name in $rootTemplates) {
    Copy-Item -LiteralPath (Join-Path $TemplateRoot $name) -Destination (Join-Path $UsbRoot $name) -Force
}
Get-ChildItem -LiteralPath $TemplateRoot -Filter '*.ps1' -File | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination $ToolsRoot -Force
}
Copy-Item -LiteralPath (Join-Path $DocsRoot 'LIETOSANAS-PAMACIBA-LV.txt') -Destination (Join-Path $UsbRoot 'LIETOSANAS-PAMACIBA-LV.txt') -Force
Copy-Item -LiteralPath (Join-Path $DocsRoot 'USER-GUIDE-EN.txt') -Destination (Join-Path $UsbRoot 'USER-GUIDE-EN.txt') -Force
Copy-Item -LiteralPath (Join-Path $DocsRoot 'CHANGELOG.txt') -Destination (Join-Path $UsbRoot 'CHANGELOG.txt') -Force

Set-Content -LiteralPath (Join-Path $UsbRoot 'portable.id') -Value $portableId -Encoding ASCII -NoNewline

$nodeVersion = (& $NodeExe --version).Trim()
$packageInfo = [ordered]@{
    name = $AppName
    version = $Version
    releaseName = $ReleaseName
    releaseArchive = $ArchiveName
    releaseStage = $ReleaseStage
    builderVersion = $BuilderVersion
    author = $Author
    website = $Website
    tagline = $Tagline
    portableId = $portableId
    builtAt = (Get-Date).ToString('o')
    architecture = $env:PROCESSOR_ARCHITECTURE
    nodeRuntime = $nodeVersion
    minecraftEdition = 'java'
    documentation = @('README-FIRST.txt', 'LIETOSANAS-PAMACIBA-LV.txt', 'USER-GUIDE-EN.txt', 'CHANGELOG.txt')
    dependencyOptimization = [ordered]@{
        beforeBytes = $optimization.beforeBytes
        afterBytes = $optimization.afterBytes
        savedBytes = $optimization.savedBytes
        removedFiles = $optimization.removedFiles
        removedDirs = $optimization.removedDirs
    }
    minecraftDataOptimization = [ordered]@{
        mode = 'java-only'
        bedrockBeforeBytes = $javaDataOptimization.beforeBytes
        bedrockAfterBytes = $javaDataOptimization.afterBytes
        savedBytes = $javaDataOptimization.savedBytes
        removedItems = $javaDataOptimization.removedItems
        bedrockCommonPreserved = $true
    }
}
$packageInfo | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $UsbRoot 'package-info.json') -Encoding UTF8

$versionText = @"
$AppName
Version $Version
Windows $ArchitectureLabel
Minecraft Java Edition
Release stage: $ReleaseStage

Created by $Author
$Tagline
$Website

Release package: $ArchiveName
Release Builder: $BuilderVersion
Build type: Stable Release
Built: $((Get-Date).ToString('yyyy-MM-dd HH:mm:ss zzz'))
"@
Set-Content -LiteralPath (Join-Path $UsbRoot 'VERSION.txt') -Value $versionText -Encoding UTF8

$readme = @"
============================================================
 $AppName v$Version
 Windows $ArchitectureLabel | Minecraft Java Edition
 Stable Release

 $Tagline
 $Website
============================================================

LATVISKI
--------

KO MAN PALAIST?

Lietot programmu Portable režīmā bez instalēšanas:
  -> RUN-PORTABLE.cmd

Instalēt programmu šajā datorā:
  -> INSTALL.cmd

Pārbaudīt, vai release var startēt uz šī datora:
  -> SELF-TEST.cmd

Atinstalēt Installed versiju no šī datora:
  -> UNINSTALL-FROM-PC.cmd

Izdzēst tikai šīs Portable pakotnes privātos datus no datora:
  -> CLEAN-PORTABLE-DATA.cmd

Pilna lietošanas pamācība latviski:
  -> LIETOSANAS-PAMACIBA-LV.txt


ENGLISH
-------

WHAT SHOULD I RUN?

Use the application in Portable mode without installing:
  -> RUN-PORTABLE.cmd

Install the application on this PC:
  -> INSTALL.cmd

Check whether this release can start on this PC:
  -> SELF-TEST.cmd

Uninstall the Installed version from this PC:
  -> UNINSTALL-FROM-PC.cmd

Remove only this Portable package's private data from this PC:
  -> CLEAN-PORTABLE-DATA.cmd

Full user guide in English:
  -> USER-GUIDE-EN.txt


IMPORTANT / SVARĪGI
-------------------
- This release supports Minecraft Java Edition servers. Bedrock Edition is not supported.
- Šis release atbalsta Minecraft Java Edition serverus. Bedrock Edition netiek atbalstīts.
- Passwords are NOT included in this ZIP/release package.
- Paroles NAV iekļautas ZIP/release pakotnē.
- Portable and Installed modes use separate private-data storage. After a fresh install,
  a /login password may need to be saved once again for the Installed profile.

Version / Versija: $Version
Builder: $BuilderVersion
Release: $ReleaseName
Portable ID: $portableId

Created by / Autors: $Author
$Tagline
$Website
"@
Set-Content -LiteralPath (Join-Path $UsbRoot 'README-FIRST.txt') -Value $readme -Encoding UTF8

Write-Step 'Verifying copied application files'
Assert-FileMatch -Source (Join-Path $ProjectRoot 'manager.js') -Destination (Join-Path $AppRoot 'manager.js') -Label 'manager.js'
Assert-FileMatch -Source (Join-Path $ProjectRoot 'package.json') -Destination (Join-Path $AppRoot 'package.json') -Label 'package.json'
Assert-FileMatch -Source (Join-Path $ProjectRoot 'decrypt-password.ps1') -Destination (Join-Path $AppRoot 'decrypt-password.ps1') -Label 'decrypt-password.ps1'
Assert-FileMatch -Source (Join-Path $ProjectRoot 'save-secret.ps1') -Destination (Join-Path $AppRoot 'save-secret.ps1') -Label 'save-secret.ps1'
Assert-TreeMatch -SourceRoot (Join-Path $ProjectRoot 'core') -DestinationRoot (Join-Path $AppRoot 'core') -Label 'core'
Assert-TreeMatch -SourceRoot (Join-Path $ProjectRoot 'web') -DestinationRoot (Join-Path $AppRoot 'web') -Label 'web'

foreach ($name in $rootTemplates) {
    Assert-FileMatch -Source (Join-Path $TemplateRoot $name) -Destination (Join-Path $UsbRoot $name) -Label "USB launcher $name"
}
Get-ChildItem -LiteralPath $TemplateRoot -Filter '*.ps1' -File | ForEach-Object {
    Assert-FileMatch -Source $_.FullName -Destination (Join-Path $ToolsRoot $_.Name) -Label "USB tool $($_.Name)"
}
Assert-FileMatch -Source (Join-Path $DocsRoot 'LIETOSANAS-PAMACIBA-LV.txt') -Destination (Join-Path $UsbRoot 'LIETOSANAS-PAMACIBA-LV.txt') -Label 'Latvian user guide'
Assert-FileMatch -Source (Join-Path $DocsRoot 'USER-GUIDE-EN.txt') -Destination (Join-Path $UsbRoot 'USER-GUIDE-EN.txt') -Label 'English user guide'
Assert-FileMatch -Source (Join-Path $DocsRoot 'CHANGELOG.txt') -Destination (Join-Path $UsbRoot 'CHANGELOG.txt') -Label 'Changelog'
Write-Ok 'USB launcher/installer/uninstaller/documentation files MATCH source'

$BuiltNode = Join-Path $AppRoot 'runtime\node.exe'
if (-not (Test-Path -LiteralPath $BuiltNode)) {
    throw 'Bundled Node runtime is missing from the build.'
}
$builtNodeVersion = (& $BuiltNode --version).Trim()
if ($LASTEXITCODE -ne 0 -or -not $builtNodeVersion) {
    throw 'Bundled Node runtime failed to execute.'
}
Write-Ok "Bundled Node runtime works ($builtNodeVersion)"

$BuiltMeta = Read-AppMeta -NodeExe $BuiltNode -Path (Join-Path $AppRoot 'core\app-meta.js')
if ([string]$BuiltMeta.version -ne $Version) {
    throw "Built app version mismatch. Source=$Version Build=$($BuiltMeta.version)"
}
Write-Ok "Built application version MATCH ($Version)"

$builtPhysicsFile = Join-Path $AppRoot 'node_modules\mineflayer\lib\plugins\physics.js'
$builtPhysicsText = Get-Content -LiteralPath $builtPhysicsFile -Raw
if ($builtPhysicsText -notmatch "write\('tick_end'" -and $builtPhysicsText -notmatch 'write\("tick_end"') {
    throw 'Built Mineflayer does not contain the required client tick_end patch.'
}
Write-Ok 'Mineflayer tick_end patch present in build'

Write-Step 'Checking built JavaScript syntax with bundled Node'
$builtJsFiles = @(
    (Join-Path $AppRoot 'manager.js'),
    (Join-Path $AppRoot 'web\app.js')
)
$builtJsFiles += Get-ChildItem -LiteralPath (Join-Path $AppRoot 'core') -Filter '*.js' -File | Select-Object -ExpandProperty FullName
foreach ($file in $builtJsFiles) {
    & $BuiltNode --check $file
    if ($LASTEXITCODE -ne 0) {
        throw "Built JavaScript syntax check failed: $file"
    }
}
Write-Ok 'Built JavaScript syntax OK'

Write-Step 'Checking Java-only minecraft-data layout'
$builtMinecraftDataRoot = Join-Path $AppRoot 'node_modules\minecraft-data\minecraft-data\data'
$builtBedrockRoot = Join-Path $builtMinecraftDataRoot 'bedrock'
$builtBedrockCommon = Join-Path $builtBedrockRoot 'common'
$builtPcRoot = Join-Path $builtMinecraftDataRoot 'pc'
if (-not (Test-Path -LiteralPath $builtPcRoot)) { throw 'Built Java minecraft-data directory is missing.' }
if (-not (Test-Path -LiteralPath $builtBedrockCommon)) { throw 'Built Bedrock common metadata directory is missing.' }
foreach ($name in @('protocolVersions.json', 'versions.json', 'legacy.json')) {
    if (-not (Test-Path -LiteralPath (Join-Path $builtBedrockCommon $name))) {
        throw "Built Bedrock common metadata file is missing: $name"
    }
}
$unexpectedBedrock = @(Get-ChildItem -LiteralPath $builtBedrockRoot -Force | Where-Object { $_.Name -ine 'common' })
if ($unexpectedBedrock.Count -gt 0) { throw 'Built package still contains Bedrock version payload.' }
Write-Ok 'Java data retained; Bedrock version payload removed; Bedrock common metadata preserved'

Write-Step 'Checking optimized runtime dependencies'
Push-Location $AppRoot
try {
    $dependencyProbe = @'
require('express')
require('mineflayer')
require('minecraft-protocol')
const minecraftData = require('minecraft-data')
const md = minecraftData('1.21.11')
if (!md || !md.version) throw new Error('minecraft-data 1.21.11 failed')
if (md.type !== 'pc') throw new Error(`Expected Java/pc minecraft-data, got ${md.type}`)
if (!minecraftData.supportedVersions || !Array.isArray(minecraftData.supportedVersions.pc) || minecraftData.supportedVersions.pc.length === 0) {
  throw new Error('minecraft-data Java supportedVersions missing')
}
'@
    & $BuiltNode -e $dependencyProbe
    if ($LASTEXITCODE -ne 0) { throw 'Optimized runtime dependency probe failed.' }
}
finally { Pop-Location }
Write-Ok 'Optimized Java runtime dependencies load correctly'

Write-Step 'Final security verification'
if (Test-Path -LiteralPath (Join-Path $AppRoot 'secret.dat')) {
    throw 'SECURITY CHECK FAILED: secret.dat is present in the USB package.'
}
$secretFiles = @(Get-ChildItem -LiteralPath (Join-Path $AppRoot 'data\secrets') -File -Force -ErrorAction SilentlyContinue)
if ($secretFiles.Count -gt 0) {
    throw 'SECURITY CHECK FAILED: data\secrets is not empty.'
}
if (Test-Path -LiteralPath (Join-Path $AppRoot 'data\microsoft-auth')) {
    throw 'SECURITY CHECK FAILED: Microsoft auth cache is present in the USB package.'
}
if (@(Get-ChildItem -LiteralPath $UsbRoot -Directory -Recurse -Force | Where-Object { $_.Name -eq '_ARCHIVE' }).Count -gt 0) {
    throw 'SECURITY CHECK FAILED: _ARCHIVE is present in the USB package.'
}
Write-Ok 'No packaged DPAPI secrets'
Write-Ok 'No packaged Microsoft auth cache'
Write-Ok 'No source _ARCHIVE directory in package'

$info = Get-Content -LiteralPath (Join-Path $UsbRoot 'package-info.json') -Raw | ConvertFrom-Json
if ([string]$info.version -ne $Version) {
    throw 'package-info.json version mismatch.'
}
if ([string]$info.builderVersion -ne $BuilderVersion) {
    throw 'package-info.json builder version mismatch.'
}
if ([string]$info.portableId -ne $portableId) {
    throw 'package-info.json portable ID mismatch.'
}
if ([string]$info.minecraftEdition -ne 'java') {
    throw 'package-info.json Minecraft edition mismatch; expected java.'
}
if ([string]$info.releaseStage -ne $ReleaseStage) {
    throw 'package-info.json release stage mismatch.'
}
if ([string]$info.releaseArchive -ne $ArchiveName) {
    throw 'package-info.json release archive name mismatch.'
}
$builtPortableId = Read-ValidPortableId (Join-Path $UsbRoot 'portable.id')
if ($builtPortableId -ne $portableId) {
    throw 'Built portable.id does not match stable .portable-id.'
}
Write-Ok "Stable portable ID MATCH ($portableId)"
$readmeText = Get-Content -LiteralPath (Join-Path $UsbRoot 'README-FIRST.txt') -Raw
if ($readmeText -notmatch [regex]::Escape("$AppName v$Version")) {
    throw 'README-FIRST.txt version mismatch.'
}
if ($readmeText -notmatch 'LATVISKI' -or $readmeText -notmatch 'ENGLISH') {
    throw 'README-FIRST.txt bilingual sections are missing.'
}
Write-Ok 'README/package-info/release metadata MATCH'
Write-Ok 'Bilingual README present'

Write-Step 'Creating build integrity manifest'
$manifestTargets = @(
    (Join-Path $AppRoot 'manager.js'),
    (Join-Path $AppRoot 'package.json'),
    (Join-Path $AppRoot 'decrypt-password.ps1'),
    (Join-Path $AppRoot 'save-secret.ps1'),
    (Join-Path $AppRoot 'node_modules\mineflayer\lib\plugins\physics.js'),
    (Join-Path $AppRoot 'runtime\node.exe')
)
$manifestTargets += Get-ChildItem -LiteralPath (Join-Path $AppRoot 'core') -File -Recurse | Select-Object -ExpandProperty FullName
$manifestTargets += Get-ChildItem -LiteralPath (Join-Path $AppRoot 'web') -File -Recurse | Select-Object -ExpandProperty FullName
$manifestTargets += Get-ChildItem -LiteralPath $ToolsRoot -File -Recurse | Select-Object -ExpandProperty FullName
foreach ($name in $rootTemplates) {
    $manifestTargets += (Join-Path $UsbRoot $name)
}
$manifestTargets += @(
    (Join-Path $UsbRoot 'package-info.json'),
    (Join-Path $UsbRoot 'VERSION.txt'),
    (Join-Path $UsbRoot 'README-FIRST.txt'),
    (Join-Path $UsbRoot 'LIETOSANAS-PAMACIBA-LV.txt'),
    (Join-Path $UsbRoot 'USER-GUIDE-EN.txt'),
    (Join-Path $UsbRoot 'CHANGELOG.txt'),
    (Join-Path $UsbRoot 'portable.id')
)

$manifestEntries = @()
foreach ($target in $manifestTargets | Sort-Object -Unique) {
    $relative = $target.Substring($UsbRoot.Length).TrimStart('\')
    $manifestEntries += [ordered]@{
        path = $relative
        sha256 = Get-Sha256 $target
        size = (Get-Item -LiteralPath $target).Length
    }
}

$manifest = [ordered]@{
    appName = $AppName
    appVersion = $Version
    builderVersion = $BuilderVersion
    builtAt = (Get-Date).ToString('o')
    files = $manifestEntries
}
$manifest | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $UsbRoot 'BUILD-MANIFEST.json') -Encoding UTF8
Write-Ok "Build manifest created ($($manifestEntries.Count) key files)"

Write-Step 'Clean-PC package simulation'
$selfTestScript = Join-Path $ToolsRoot 'self-test.ps1'
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $selfTestScript -UsbRoot $UsbRoot
if ($LASTEXITCODE -ne 0) {
    throw 'Clean-PC package self-test failed.'
}
Write-Ok 'Clean-PC package simulation PASSED'

Write-Step 'Creating final distributable ZIP'
$ZipPath = New-VerifiedReleaseArchive -SourceDirectory $UsbRoot -BuildDirectory $BuildRoot -ReleaseFolderName $ReleaseName -ArchiveFileName $ArchiveName
$zipHash = Get-Sha256 $ZipPath
$zipSizeBytes = (Get-Item -LiteralPath $ZipPath).Length
$shaFile = Join-Path $BuildRoot ($ArchiveName + '.sha256.txt')
Set-Content -LiteralPath $shaFile -Value ("$zipHash  $ArchiveName") -Encoding ASCII
Write-Ok "Final ZIP created and verified: $ArchiveName"
Write-Ok "SHA256: $zipHash"

$sizeBytes = (Get-ChildItem -LiteralPath $UsbRoot -File -Recurse | Measure-Object -Property Length -Sum).Sum
$sizeMb = [math]::Round($sizeBytes / 1MB, 1)
$totalOptimizationSaved = [int64]$optimization.savedBytes + [int64]$javaDataOptimization.savedBytes

Write-Host ''
Write-Host '===============================================' -ForegroundColor Green
Write-Host ' USB BUILD COMPLETED AND VERIFIED' -ForegroundColor Green
Write-Host '===============================================' -ForegroundColor Green
Write-Host "Application: $AppName v$Version"
Write-Host "Release:     $ReleaseName"
Write-Host "Stage:       $ReleaseStage"
Write-Host "Builder:     v$BuilderVersion"
Write-Host "Folder:      $UsbRoot"
Write-Host "Archive:     $ZipPath"
Write-Host "Folder size: $sizeMb MB"
Write-Host "ZIP size:    $([math]::Round($zipSizeBytes / 1MB, 1)) MB"
Write-Host "ZIP SHA256:  $zipHash"
Write-Host "Saved:       $(Format-Mb $optimization.savedBytes) from generic node_modules cleanup"
Write-Host "Saved:       $(Format-Mb $javaDataOptimization.savedBytes) from Bedrock version-data removal"
Write-Host "Saved total: $(Format-Mb $totalOptimizationSaved)"
Write-Host "Edition:     Minecraft Java Edition"
Write-Host "Author:      $Author - $Website"
Write-Host ''
Write-Host 'Verified:'
Write-Host '  [OK] source/build application hashes'
Write-Host '  [OK] USB launcher/installer/uninstaller hashes'
Write-Host '  [OK] safe installed-uninstaller bootstrap + install marker'
Write-Host '  [OK] stable Portable identity across future builds'
Write-Host '  [OK] application version'
Write-Host '  [OK] bilingual README + LV/EN user guides + changelog'
Write-Host '  [OK] release/package metadata'
Write-Host '  [OK] bundled Node runtime'
Write-Host '  [OK] Mineflayer tick_end patch'
Write-Host '  [OK] no DPAPI secrets'
Write-Host '  [OK] no Microsoft auth cache'
Write-Host '  [OK] build integrity manifest'
Write-Host '  [OK] clean-PC isolated launch simulation'
Write-Host '  [OK] Java-only minecraft-data packaging (all PC data retained)'
Write-Host '  [OK] optimized runtime dependency probe'
Write-Host '  [OK] final distributable ZIP contents verified'
Write-Host ''
Write-Host 'FINAL STABLE RELEASE READY:' -ForegroundColor Green
Write-Host "  $ZipPath" -ForegroundColor Green
Write-Host "  SHA256: $zipHash"
Write-Host ''
Write-Host "For USB use, copy the $ReleaseName folder or extract the final ZIP."
Write-Host 'README-FIRST.txt contains the bilingual quick start.'
Write-Host 'Use INSTALL.cmd for installed mode or RUN-PORTABLE.cmd for portable mode.'
Write-Host ''

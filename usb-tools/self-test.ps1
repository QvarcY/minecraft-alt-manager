param(
    [string]$UsbRoot = ''
)

$ErrorActionPreference = 'Stop'

function Ok([string]$Text) { Write-Host "[OK] $Text" -ForegroundColor Green }
function Step([string]$Text) { Write-Host "`n==> $Text" -ForegroundColor Cyan }

if (-not $UsbRoot) {
    $ToolsDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    $UsbRoot = Split-Path -Parent $ToolsDir
}
$UsbRoot = (Resolve-Path -LiteralPath $UsbRoot).Path.TrimEnd('\')
$AppRoot = Join-Path $UsbRoot 'app'
$NodeExe = Join-Path $AppRoot 'runtime\node.exe'
$InfoFile = Join-Path $UsbRoot 'package-info.json'
$PortableIdFile = Join-Path $UsbRoot 'portable.id'

$tempRoot = Join-Path $env:TEMP ("MinecraftAltManager-SelfTest-" + [guid]::NewGuid().ToString('N'))
$proc = $null
$oldEnv = @{}

try {
    Step 'Package files'
    foreach ($path in @(
        $NodeExe,
        (Join-Path $AppRoot 'manager.js'),
        (Join-Path $AppRoot 'core\app-meta.js'),
        (Join-Path $AppRoot 'web\app.js'),
        (Join-Path $AppRoot 'node_modules\mineflayer'),
        $InfoFile,
        $PortableIdFile
    )) {
        if (-not (Test-Path -LiteralPath $path)) { throw "Missing package item: $path" }
    }
    Ok 'Required package files found'

    $portableId = (Get-Content -LiteralPath $PortableIdFile -Raw).Trim()
    if ($portableId -notmatch '^[0-9a-fA-F]{32}$') { throw 'portable.id is invalid.' }
    Ok "Portable ID valid ($portableId)"

    $info = Get-Content -LiteralPath $InfoFile -Raw | ConvertFrom-Json
    Ok "Release metadata: $($info.name) v$($info.version)"
    if ([string]$info.minecraftEdition -ne 'java') { throw 'This package is not marked as a Java Edition release.' }

    Step 'Minecraft Java Edition data'
    $minecraftDataRoot = Join-Path $AppRoot 'node_modules\minecraft-data\minecraft-data\data'
    $pcRoot = Join-Path $minecraftDataRoot 'pc'
    $bedrockRoot = Join-Path $minecraftDataRoot 'bedrock'
    $bedrockCommon = Join-Path $bedrockRoot 'common'
    if (-not (Test-Path -LiteralPath $pcRoot)) { throw 'Java/PC minecraft-data is missing.' }
    if (-not (Test-Path -LiteralPath $bedrockCommon)) { throw 'Bedrock common metadata required by minecraft-data loader is missing.' }
    foreach ($name in @('protocolVersions.json', 'versions.json', 'legacy.json')) {
        if (-not (Test-Path -LiteralPath (Join-Path $bedrockCommon $name))) { throw "Required Bedrock common metadata missing: $name" }
    }
    $unexpectedBedrock = @(Get-ChildItem -LiteralPath $bedrockRoot -Force | Where-Object { $_.Name -ine 'common' })
    if ($unexpectedBedrock.Count -gt 0) { throw 'Unexpected Bedrock version payload found in Java-only release.' }
    Ok 'All Java data present; Bedrock version payload removed safely'

    Step 'Security check'
    if (Test-Path -LiteralPath (Join-Path $AppRoot 'secret.dat')) { throw 'secret.dat is packaged.' }
    $secretDir = Join-Path $AppRoot 'data\secrets'
    if (Test-Path -LiteralPath $secretDir) {
        $secretFiles = @(Get-ChildItem -LiteralPath $secretDir -File -Force -ErrorAction SilentlyContinue)
        if ($secretFiles.Count -gt 0) { throw 'Packaged DPAPI secret files found.' }
    }
    if (Test-Path -LiteralPath (Join-Path $AppRoot 'data\microsoft-auth')) { throw 'Packaged Microsoft auth cache found.' }
    Ok 'No packaged passwords or Microsoft auth cache'

    Step 'Bundled Node runtime'
    $nodeVersion = (& $NodeExe --version).Trim()
    if ($LASTEXITCODE -ne 0 -or -not $nodeVersion) { throw 'Bundled Node runtime failed.' }
    Ok "Bundled Node works ($nodeVersion)"

    Step 'JavaScript and runtime dependencies'
    $checkFiles = @(
        (Join-Path $AppRoot 'manager.js'),
        (Join-Path $AppRoot 'web\app.js')
    )
    $checkFiles += Get-ChildItem -LiteralPath (Join-Path $AppRoot 'core') -Filter '*.js' -File | Select-Object -ExpandProperty FullName
    foreach ($file in $checkFiles) {
        & $NodeExe --check $file
        if ($LASTEXITCODE -ne 0) { throw "JavaScript syntax failed: $file" }
    }
    Ok 'Application JavaScript syntax OK'

    Push-Location $AppRoot
    try {
        $probe = @'
require('express')
require('mineflayer')
require('minecraft-protocol')
const minecraftData = require('minecraft-data')
const md = minecraftData('1.21.11')
if (!md || !md.version) throw new Error('minecraft-data 1.21.11 failed')
if (md.type !== 'pc') throw new Error(`Expected Java/pc minecraft-data, got ${md.type}`)
if (!minecraftData.supportedVersions || !Array.isArray(minecraftData.supportedVersions.pc) || minecraftData.supportedVersions.pc.length === 0) throw new Error('Java supportedVersions missing')
process.stdout.write('Java runtime dependencies OK')
'@
        $probeOut = & $NodeExe -e $probe
        if ($LASTEXITCODE -ne 0) { throw 'Runtime dependency load failed.' }
        Ok $probeOut
    }
    finally { Pop-Location }

    Step 'Isolated clean-PC launch simulation'
    $testData = Join-Path $tempRoot 'data'
    $testProfiles = Join-Path $testData 'profiles'
    New-Item -ItemType Directory -Path $testProfiles -Force | Out-Null

    $sourceProfile = Get-ChildItem -LiteralPath (Join-Path $AppRoot 'data\profiles') -Filter '*.json' -File -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($sourceProfile) {
        Copy-Item -LiteralPath $sourceProfile.FullName -Destination $testProfiles -Force
        try {
            $profileId = [string]((Get-Content -LiteralPath $sourceProfile.FullName -Raw | ConvertFrom-Json).id)
        } catch { $profileId = $sourceProfile.BaseName }
        if (-not $profileId) { $profileId = $sourceProfile.BaseName }
    }
    else {
        $profileId = 'self-test'
        $profile = [ordered]@{
            id = $profileId
            name = 'Self Test'
            connection = [ordered]@{ host='example.invalid'; port=25565; version='1.21.11'; username='SELF_TEST'; auth='offline' }
            reconnect = [ordered]@{ enabled=$false; delayMs=15000; backoffEnabled=$true; maxDelayMs=300000; maxAttempts=5; resetAfterMs=120000 }
            compatibility = [ordered]@{ tickEndGuard=$true; disablePhysicsDuringConfiguration=$true }
            workflow = [ordered]@{ steps=@() }
        }
        $profile | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $testProfiles 'self-test.json') -Encoding ASCII
    }

    [ordered]@{ activeProfileId=$profileId; autoStart=$false } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $testData 'settings.json') -Encoding ASCII

    $listener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, 0)
    $listener.Start()
    $port = ([System.Net.IPEndPoint]$listener.LocalEndpoint).Port
    $listener.Stop()

    foreach ($name in @('MAM_MODE','MAM_PROFILE_DATA_DIR','MAM_SECRETS_DIR','MAM_AUTH_DATA_DIR','MAM_WEB_PORT','MAM_PID_FILE')) {
        $oldEnv[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
    }
    $env:MAM_MODE = 'selftest'
    $env:MAM_PROFILE_DATA_DIR = $testData
    $env:MAM_SECRETS_DIR = Join-Path $testData 'secrets'
    $env:MAM_AUTH_DATA_DIR = Join-Path $testData 'microsoft-auth'
    $env:MAM_WEB_PORT = [string]$port
    $env:MAM_PID_FILE = Join-Path $tempRoot 'manager.pid'

    $proc = Start-Process -FilePath $NodeExe -ArgumentList @('manager.js') -WorkingDirectory $AppRoot -WindowStyle Hidden -PassThru
    $url = "http://127.0.0.1:$port/api/status"
    $deadline = (Get-Date).AddSeconds(12)
    $status = $null
    do {
        Start-Sleep -Milliseconds 250
        try { $status = Invoke-RestMethod -Uri $url -Method Get -TimeoutSec 1 } catch {}
    } while (-not $status -and (Get-Date) -lt $deadline)

    if (-not $status) { throw 'Packaged Manager did not start in isolated self-test mode.' }
    if ([string]$status.appMode -ne 'selftest') { throw "Unexpected self-test app mode: $($status.appMode)" }
    if ([string]$status.appVersion -ne [string]$info.version) { throw "Version mismatch in self-test: $($status.appVersion) vs $($info.version)" }
    if ($status.running) { throw 'Self-test profile unexpectedly auto-started a Minecraft connection.' }
    Ok "Manager started from bundled runtime on isolated port $port"

    try {
        Invoke-RestMethod -Uri "http://127.0.0.1:$port/api/shutdown" -Method Post -Headers @{ 'X-Manager-Control'='1' } -ContentType 'application/json' -Body '{}' -TimeoutSec 2 | Out-Null
    } catch {}
    if ($proc) { $proc.WaitForExit(5000) | Out-Null }
    if ($proc -and -not $proc.HasExited) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue }
    $proc = $null
    Ok 'Manager shutdown completed'

    Write-Host "`n===============================================" -ForegroundColor Green
    Write-Host ' PACKAGE SELF-TEST PASSED' -ForegroundColor Green
    Write-Host '===============================================' -ForegroundColor Green
    Write-Host 'This package can start without a system Node.js installation.'
    Write-Host 'No real Minecraft server connection was made during this test.'
    exit 0
}
catch {
    Write-Host "`n[FAIL] $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
finally {
    if ($proc -and -not $proc.HasExited) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue }
    foreach ($name in $oldEnv.Keys) {
        [Environment]::SetEnvironmentVariable($name, $oldEnv[$name], 'Process')
    }
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

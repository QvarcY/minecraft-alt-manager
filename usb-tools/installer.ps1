$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$ToolsDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$PackageRoot = Split-Path -Parent $ToolsDir
$SourceApp = Join-Path $PackageRoot 'app'
$InfoFile = Join-Path $PackageRoot 'package-info.json'
$InstallDir = Join-Path $env:LOCALAPPDATA 'QvarcY\MinecraftAltManager'
$InstalledTools = Join-Path $InstallDir 'tools'
$RegistryPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\MinecraftAltManager_QvarcY'
$InstallMarker = Join-Path $InstallDir '.mam-installed.json'

$AppName = 'Minecraft ALT Manager'
$Version = 'unknown'
$Author = 'QvarcY'
$Website = 'https://kas.id.lv'
$Tagline = 'IT solutions by QvarcY'

if (Test-Path -LiteralPath $InfoFile) {
    try {
        $info = Get-Content -LiteralPath $InfoFile -Raw | ConvertFrom-Json
        if ($info.name) { $AppName = [string]$info.name }
        if ($info.version) { $Version = [string]$info.version }
        if ($info.author) { $Author = [string]$info.author }
        if ($info.website) { $Website = [string]$info.website }
        if ($info.tagline) { $Tagline = [string]$info.tagline }
    } catch {}
}

function Show-Error([string]$text) {
    [System.Windows.Forms.MessageBox]::Show($text, $AppName, 'OK', 'Error') | Out-Null
}

function Copy-Tree([string]$Source, [string]$Destination, [switch]$ExcludeData) {
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null

    $args = @(
        $Source,
        $Destination,
        '/E',
        '/R:2',
        '/W:1',
        '/NFL',
        '/NDL',
        '/NJH',
        '/NJS',
        '/NP'
    )

    if ($ExcludeData) {
        $args += @('/XD', (Join-Path $Source 'data'))
    }

    & robocopy @args | Out-Null
    $code = $LASTEXITCODE
    if ($code -gt 7) {
        throw "File copy failed. ROBOCOPY exit code: $code"
    }
}

function New-Shortcut([string]$Path, [string]$Target, [string]$Arguments, [string]$WorkingDir, [string]$Description) {
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($Path)
    $shortcut.TargetPath = $Target
    $shortcut.Arguments = $Arguments
    $shortcut.WorkingDirectory = $WorkingDir
    $shortcut.Description = $Description
    $shortcut.Save()
}

function Test-InstalledManager {
    if (Test-Path -LiteralPath $InstallMarker) { return $true }

    $managerFile = Join-Path $InstallDir 'manager.js'
    $runtimeFile = Join-Path $InstallDir 'runtime\node.exe'
    return ((Test-Path -LiteralPath $managerFile) -and (Test-Path -LiteralPath $runtimeFile))
}

function Stop-ExistingManager {
    $stopScript = Join-Path $InstalledTools 'stop-manager.ps1'
    if (Test-Path -LiteralPath $stopScript) {
        try {
            & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $stopScript -AppRoot $InstallDir | Out-Null
            Start-Sleep -Milliseconds 500
        } catch {}
    }
}

if (-not (Test-Path -LiteralPath $SourceApp)) {
    Show-Error "The USB package is incomplete. The app folder was not found.`n`nRebuild the USB package with BUILD-USB.cmd."
    exit 1
}

if (-not (Test-Path -LiteralPath (Join-Path $SourceApp 'runtime\node.exe'))) {
    Show-Error "The USB package does not contain the bundled Node runtime.`n`nRebuild it on the source PC."
    exit 1
}

$form = New-Object System.Windows.Forms.Form
$form.Text = "$AppName Setup"
$form.StartPosition = 'CenterScreen'
$form.ClientSize = New-Object System.Drawing.Size(560, 500)
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$form.MinimizeBox = $false
$form.BackColor = [System.Drawing.Color]::FromArgb(18, 25, 35)
$form.ForeColor = [System.Drawing.Color]::FromArgb(238, 245, 252)
$form.Font = New-Object System.Drawing.Font('Segoe UI', 9)

$title = New-Object System.Windows.Forms.Label
$title.Text = $AppName
$title.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 22)
$title.Location = New-Object System.Drawing.Point(28, 24)
$title.Size = New-Object System.Drawing.Size(500, 42)
$form.Controls.Add($title)

$brand = New-Object System.Windows.Forms.Label
$brand.Text = "$Tagline  ·  $Website"
$brand.ForeColor = [System.Drawing.Color]::FromArgb(143, 162, 183)
$brand.Location = New-Object System.Drawing.Point(31, 70)
$brand.Size = New-Object System.Drawing.Size(500, 24)
$form.Controls.Add($brand)

$intro = New-Object System.Windows.Forms.Label
$intro.Text = "Install the Manager locally for normal use. The same USB also supports RUN-PORTABLE.cmd without installation."
$intro.ForeColor = [System.Drawing.Color]::FromArgb(180, 194, 209)
$intro.Location = New-Object System.Drawing.Point(31, 111)
$intro.Size = New-Object System.Drawing.Size(490, 48)
$form.Controls.Add($intro)

$pathLabel = New-Object System.Windows.Forms.Label
$pathLabel.Text = 'Installation location'
$pathLabel.Location = New-Object System.Drawing.Point(31, 171)
$pathLabel.Size = New-Object System.Drawing.Size(190, 22)
$form.Controls.Add($pathLabel)

$pathBox = New-Object System.Windows.Forms.TextBox
$pathBox.Text = $InstallDir
$pathBox.ReadOnly = $true
$pathBox.Location = New-Object System.Drawing.Point(31, 196)
$pathBox.Size = New-Object System.Drawing.Size(495, 27)
$pathBox.BackColor = [System.Drawing.Color]::FromArgb(11, 17, 24)
$pathBox.ForeColor = [System.Drawing.Color]::FromArgb(238, 245, 252)
$form.Controls.Add($pathBox)

$existing = Test-InstalledManager
$existingLabel = New-Object System.Windows.Forms.Label
$existingLabel.Text = if ($existing) { 'Existing installation detected. Profiles, passwords and settings will be preserved.' } else { 'Fresh installation. Profiles included in this USB package will be copied.' }
$existingLabel.ForeColor = if ($existing) { [System.Drawing.Color]::FromArgb(240, 182, 79) } else { [System.Drawing.Color]::FromArgb(82, 218, 141) }
$existingLabel.Location = New-Object System.Drawing.Point(31, 230)
$existingLabel.Size = New-Object System.Drawing.Size(500, 36)
$form.Controls.Add($existingLabel)

$desktopCheck = New-Object System.Windows.Forms.CheckBox
$desktopCheck.Text = 'Create Desktop shortcut'
$desktopCheck.Checked = $true
$desktopCheck.Location = New-Object System.Drawing.Point(31, 278)
$desktopCheck.Size = New-Object System.Drawing.Size(300, 26)
$form.Controls.Add($desktopCheck)

$startupCheck = New-Object System.Windows.Forms.CheckBox
$startupCheck.Text = 'Start Manager automatically with Windows'
$startupCheck.Checked = $false
$startupCheck.Location = New-Object System.Drawing.Point(31, 309)
$startupCheck.Size = New-Object System.Drawing.Size(360, 26)
$form.Controls.Add($startupCheck)

$launchCheck = New-Object System.Windows.Forms.CheckBox
$launchCheck.Text = 'Launch Manager after installation'
$launchCheck.Checked = $true
$launchCheck.Location = New-Object System.Drawing.Point(31, 340)
$launchCheck.Size = New-Object System.Drawing.Size(320, 26)
$form.Controls.Add($launchCheck)

$progress = New-Object System.Windows.Forms.ProgressBar
$progress.Location = New-Object System.Drawing.Point(31, 382)
$progress.Size = New-Object System.Drawing.Size(495, 16)
$progress.Style = 'Continuous'
$progress.Minimum = 0
$progress.Maximum = 100
$progress.Value = 0
$form.Controls.Add($progress)

$status = New-Object System.Windows.Forms.Label
$status.Text = "Ready to install $AppName v$Version"
$status.ForeColor = [System.Drawing.Color]::FromArgb(143, 162, 183)
$status.Location = New-Object System.Drawing.Point(31, 407)
$status.Size = New-Object System.Drawing.Size(495, 28)
$form.Controls.Add($status)

$installButton = New-Object System.Windows.Forms.Button
$installButton.Text = if ($existing) { 'UPDATE / REPAIR' } else { 'INSTALL' }
$installButton.Location = New-Object System.Drawing.Point(366, 447)
$installButton.Size = New-Object System.Drawing.Size(160, 36)
$installButton.BackColor = [System.Drawing.Color]::FromArgb(46, 170, 108)
$installButton.ForeColor = [System.Drawing.Color]::White
$installButton.FlatStyle = 'Flat'
$form.Controls.Add($installButton)

$cancelButton = New-Object System.Windows.Forms.Button
$cancelButton.Text = 'Cancel'
$cancelButton.Location = New-Object System.Drawing.Point(260, 447)
$cancelButton.Size = New-Object System.Drawing.Size(96, 36)
$cancelButton.FlatStyle = 'Flat'
$cancelButton.Add_Click({ $form.Close() })
$form.Controls.Add($cancelButton)

$installButton.Add_Click({
    $installButton.Enabled = $false
    $cancelButton.Enabled = $false
    $form.UseWaitCursor = $true

    try {
        $status.Text = 'Stopping existing Manager...'
        $progress.Value = 8
        $form.Refresh()
        Stop-ExistingManager

        $status.Text = 'Copying application files...'
        $progress.Value = 20
        $form.Refresh()

        if ($existing -and (Test-Path -LiteralPath (Join-Path $InstallDir 'data'))) {
            Copy-Tree -Source $SourceApp -Destination $InstallDir -ExcludeData
        }
        else {
            Copy-Tree -Source $SourceApp -Destination $InstallDir
        }

        New-Item -ItemType Directory -Path $InstalledTools -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $ToolsDir 'start-manager.ps1') -Destination $InstalledTools -Force
        Copy-Item -LiteralPath (Join-Path $ToolsDir 'stop-manager.ps1') -Destination $InstalledTools -Force
        Copy-Item -LiteralPath (Join-Path $ToolsDir 'uninstall-installed.ps1') -Destination $InstalledTools -Force

        $installInfo = [ordered]@{
            appName = $AppName
            version = $Version
            author = $Author
            website = $Website
            installedAt = (Get-Date).ToString('o')
            installRoot = $InstallDir
        }
        $installInfo | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $InstallMarker -Encoding UTF8

        $status.Text = 'Creating launchers...'
        $progress.Value = 50
        $form.Refresh()

        $startCmd = @"
@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\start-manager.ps1"
"@
        $stopCmd = @"
@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\stop-manager.ps1" -AppRoot "%~dp0"
"@
        $uninstallCmd = @"
@echo off
setlocal
for %%I in ("%~dp0.") do set "MAM_INSTALL=%%~fI"
set "MAM_TEMP=%TEMP%\mam-uninstall-%RANDOM%-%RANDOM%.ps1"
copy /Y "%~dp0tools\uninstall-installed.ps1" "%MAM_TEMP%" >nul
if errorlevel 1 (
    echo Unable to prepare the temporary uninstaller.
    pause
    exit /b 1
)
start "" powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "%MAM_TEMP%" -InstallDir "%MAM_INSTALL%"
exit /b 0
"@

        Set-Content -LiteralPath (Join-Path $InstallDir 'START-MANAGER.cmd') -Value $startCmd -Encoding ASCII
        Set-Content -LiteralPath (Join-Path $InstallDir 'STOP-MANAGER.cmd') -Value $stopCmd -Encoding ASCII
        Set-Content -LiteralPath (Join-Path $InstallDir 'UNINSTALL.cmd') -Value $uninstallCmd -Encoding ASCII

        $powershellExe = Join-Path $PSHOME 'powershell.exe'
        if (-not (Test-Path -LiteralPath $powershellExe)) { $powershellExe = 'powershell.exe' }
        $startScript = Join-Path $InstalledTools 'start-manager.ps1'
        $shortcutArgs = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$startScript`""

        $desktop = [Environment]::GetFolderPath('Desktop')
        $desktopShortcut = Join-Path $desktop "$AppName.lnk"
        if ($desktopCheck.Checked) {
            New-Shortcut -Path $desktopShortcut -Target $powershellExe -Arguments $shortcutArgs -WorkingDir $InstallDir -Description "$AppName by $Author"
        }
        else {
            Remove-Item -LiteralPath $desktopShortcut -Force -ErrorAction SilentlyContinue
        }

        $startMenuDir = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\QvarcY\Minecraft ALT Manager'
        New-Item -ItemType Directory -Path $startMenuDir -Force | Out-Null
        New-Shortcut -Path (Join-Path $startMenuDir "$AppName.lnk") -Target $powershellExe -Arguments $shortcutArgs -WorkingDir $InstallDir -Description "$AppName by $Author"
        New-Shortcut -Path (Join-Path $startMenuDir "Uninstall $AppName.lnk") -Target (Join-Path $InstallDir 'UNINSTALL.cmd') -Arguments '' -WorkingDir $InstallDir -Description "Remove $AppName"

        $startupDir = [Environment]::GetFolderPath('Startup')
        $startupShortcut = Join-Path $startupDir "$AppName.lnk"
        if ($startupCheck.Checked) {
            $startupArgs = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$startScript`" -NoBrowser"
            New-Shortcut -Path $startupShortcut -Target $powershellExe -Arguments $startupArgs -WorkingDir $InstallDir -Description "$AppName autostart"
        }
        else {
            Remove-Item -LiteralPath $startupShortcut -Force -ErrorAction SilentlyContinue
        }

        $status.Text = 'Registering uninstaller...'
        $progress.Value = 75
        $form.Refresh()

        New-Item -Path $RegistryPath -Force | Out-Null
        New-ItemProperty -Path $RegistryPath -Name DisplayName -Value $AppName -PropertyType String -Force | Out-Null
        New-ItemProperty -Path $RegistryPath -Name DisplayVersion -Value $Version -PropertyType String -Force | Out-Null
        New-ItemProperty -Path $RegistryPath -Name Publisher -Value $Author -PropertyType String -Force | Out-Null
        New-ItemProperty -Path $RegistryPath -Name URLInfoAbout -Value $Website -PropertyType String -Force | Out-Null
        New-ItemProperty -Path $RegistryPath -Name InstallLocation -Value $InstallDir -PropertyType String -Force | Out-Null
        New-ItemProperty -Path $RegistryPath -Name UninstallString -Value (Join-Path $InstallDir 'UNINSTALL.cmd') -PropertyType String -Force | Out-Null
        New-ItemProperty -Path $RegistryPath -Name NoModify -Value 1 -PropertyType DWord -Force | Out-Null
        New-ItemProperty -Path $RegistryPath -Name NoRepair -Value 1 -PropertyType DWord -Force | Out-Null

        $progress.Value = 100
        $status.Text = "$AppName v$Version installed successfully."
        $form.Refresh()

        [System.Windows.Forms.MessageBox]::Show(
            "$AppName has been installed successfully.`n`nAuthor: $Author`n$Tagline`n$Website",
            $AppName,
            'OK',
            'Information'
        ) | Out-Null

        if ($launchCheck.Checked) {
            & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $InstalledTools 'start-manager.ps1') | Out-Null
        }

        $form.Close()
    }
    catch {
        $progress.Value = 0
        $status.Text = 'Installation failed.'
        Show-Error $_.Exception.Message
        $installButton.Enabled = $true
        $cancelButton.Enabled = $true
    }
    finally {
        $form.UseWaitCursor = $false
    }
})

[void]$form.ShowDialog()

param (
    [Parameter(Mandatory = $true)]
    [string]$SecretFile
)

$ErrorActionPreference = "Stop"

$password = [Console]::In.ReadToEnd()

if ([string]::IsNullOrEmpty($password)) {
    throw "Parole ir tuksa."
}

$directory = Split-Path -Parent $SecretFile
if (-not (Test-Path -LiteralPath $directory)) {
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
}

$secure = ConvertTo-SecureString $password -AsPlainText -Force
$encrypted = ConvertFrom-SecureString $secure
Set-Content -LiteralPath $SecretFile -Value $encrypted -Encoding UTF8 -NoNewline

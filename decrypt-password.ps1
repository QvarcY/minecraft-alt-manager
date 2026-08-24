param (
    [Parameter(Mandatory = $true)]
    [string]$SecretFile
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $SecretFile)) {
    throw "Paroles fails nav atrasts: $SecretFile"
}

$encrypted = Get-Content -LiteralPath $SecretFile -Raw -Encoding UTF8

if ([string]::IsNullOrWhiteSpace($encrypted)) {
    throw "Paroles fails ir tukss."
}

$securePassword = ConvertTo-SecureString $encrypted
$bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)

try {
    [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
}
finally {
    if ($bstr -ne [IntPtr]::Zero) {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}

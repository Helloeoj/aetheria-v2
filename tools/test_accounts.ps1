param([switch]$Integration)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$accountData = Join-Path $env:LOCALAPPDATA 'Aetheria/online'
if ($env:AETHERIA_ACCOUNT_DATA) { $accountData = $env:AETHERIA_ACCOUNT_DATA }
$accountPython = Join-Path $accountData 'venv/Scripts/python.exe'
Push-Location $repo
try {
    & $accountPython -m backend.test_runner
    if ($LASTEXITCODE) { exit $LASTEXITCODE }
    if ($Integration) {
        & $accountPython -m backend.integration_test
        exit $LASTEXITCODE
    }
} finally { Pop-Location }

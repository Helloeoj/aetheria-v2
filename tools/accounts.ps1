param(
    [ValidateSet('start','stop','status')][string]$Action = 'status'
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$accountData = Join-Path $env:LOCALAPPDATA 'Aetheria/online'
if ($env:AETHERIA_ACCOUNT_DATA) { $accountData = $env:AETHERIA_ACCOUNT_DATA }
$pidFile = Join-Path $accountData 'service.json'
$accountPython = Join-Path $accountData 'venv/Scripts/python.exe'

function Get-AccountProcess {
    if (-not (Test-Path -LiteralPath $pidFile)) { return $null }
    $saved = Get-Content -Raw -LiteralPath $pidFile | ConvertFrom-Json
    $candidate = Get-CimInstance Win32_Process -Filter "ProcessId=$($saved.pid)" -ErrorAction SilentlyContinue
    if ($candidate -and $candidate.CommandLine -match '\-m backend\.service' -and $saved.repo -eq $repo) { return $candidate }
    return $null
}

if ($Action -eq 'stop') {
    $running = Get-AccountProcess
    if ($running) { Stop-Process -Id $running.ProcessId -Force }
    Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
    Write-Output 'Account service stopped. PostgreSQL remains running for durable storage.'
    exit 0
}
if ($Action -eq 'status') {
    $running = Get-AccountProcess
    if ($running) {
        $saved = Get-Content -Raw -LiteralPath $pidFile | ConvertFrom-Json
        try {
            $health = Invoke-RestMethod -Uri "http://127.0.0.1:$($saved.port)/health" -TimeoutSec 3
            if ($health.ok -and $health.service -eq 'aetheria-accounts') {
                Write-Output "Account service ready at http://127.0.0.1:$($saved.port) ($($saved.database))."
                exit 0
            }
        } catch { }
        Write-Output 'Account service is starting or unavailable.'
        exit 1
    }
    Write-Output 'Account service stopped.'
    exit 1
}

if (Get-AccountProcess) { & $PSCommandPath status; exit $LASTEXITCODE }
New-Item -ItemType Directory -Force -Path $accountData | Out-Null
# Config, database, keys, venv and logs are private per-user files outside Git.
$identity = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
& icacls.exe $accountData '/inheritance:r' '/grant:r' "${identity}:(OI)(CI)F" 'SYSTEM:(OI)(CI)F' | Out-Null
if ($LASTEXITCODE) { throw 'Could not protect the private account data directory.' }
if (-not (Test-Path -LiteralPath $accountPython)) {
    $runtime = Join-Path $env:USERPROFILE '.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe'
    if (-not (Test-Path -LiteralPath $runtime)) { throw 'Python 3.12+ is required; set up the account runtime first.' }
    & $runtime -m venv (Join-Path $accountData 'venv')
    if ($LASTEXITCODE) { throw 'Account Python environment creation failed.' }
}
& $accountPython -c 'import django, argon2, psycopg, waitress' 2>$null
if ($LASTEXITCODE) {
    & $accountPython -m pip install -r (Join-Path $repo 'backend/requirements.txt')
    if ($LASTEXITCODE) { throw 'Account dependencies could not be installed.' }
}
$pgBin = Join-Path $accountData 'postgresql-runtime/pgsql/bin/pg_ctl.exe'
if (-not (Test-Path -LiteralPath $pgBin)) {
    $archive = Join-Path $accountData 'postgresql.zip'
    if (-not (Test-Path -LiteralPath $archive)) {
        Invoke-WebRequest -Uri 'https://get.enterprisedb.com/postgresql/postgresql-17.11-5-windows-x64-binaries.zip' -OutFile $archive
    }
    Expand-Archive -LiteralPath $archive -DestinationPath (Join-Path $accountData 'postgresql-runtime') -Force
}
$stdout = Join-Path $accountData 'service-stdout.log'
$stderr = Join-Path $accountData 'service-stderr.log'
$process = Start-Process -FilePath $accountPython -ArgumentList @('-m','backend.service') -WorkingDirectory $repo -WindowStyle Hidden -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
for ($attempt=0; $attempt -lt 60; $attempt++) {
    Start-Sleep -Milliseconds 500
    $process.Refresh()
    if ($process.HasExited) { throw "Account service could not start. Review $stderr locally (never share credentials)." }
    if (Test-Path -LiteralPath $pidFile) {
        try {
            $saved = Get-Content -Raw -LiteralPath $pidFile | ConvertFrom-Json
            $health = Invoke-RestMethod -Uri "http://127.0.0.1:$($saved.port)/health" -TimeoutSec 1
            if ($health.ok -and $health.service -eq 'aetheria-accounts') {
                Write-Output "Account service ready at http://127.0.0.1:$($saved.port) ($($saved.database))."
                exit 0
            }
        } catch { }
    }
}
throw 'Account service startup timed out. Review the private service log.'

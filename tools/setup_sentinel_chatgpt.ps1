# Optional identity-verification dependencies; no API key, account sign-in or API charge.
$ErrorActionPreference = 'Stop'
$pythonExecutable = Join-Path $env:USERPROFILE '.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe'
if (-not (Test-Path -LiteralPath $pythonExecutable)) { $pythonExecutable = (Get-Command python -ErrorAction Stop).Source }
$dependencyFolder = Join-Path $env:LOCALAPPDATA 'AetheriaSentinel/dependencies'
& $pythonExecutable -m pip install --disable-pip-version-check --target $dependencyFolder --upgrade -r (Join-Path $PSScriptRoot 'sentinel-chatgpt-requirements.txt')
if ($LASTEXITCODE -ne 0) { throw 'Optional ChatGPT dependency setup failed. Local monitoring still works.' }

# Embedded normal ChatGPT page. No model calls, account sign-in or credit purchases.
$ErrorActionPreference = 'Stop'
$pythonExecutable = Join-Path $env:USERPROFILE '.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe'
if (-not (Test-Path -LiteralPath $pythonExecutable)) { $pythonExecutable = (Get-Command python -ErrorAction Stop).Source }
$dependencyFolder = Join-Path $env:LOCALAPPDATA 'AetheriaSentinel/browser-dependencies'
& $pythonExecutable -m pip install --disable-pip-version-check --target $dependencyFolder --upgrade -r (Join-Path $PSScriptRoot 'sentinel-browser-requirements.txt')
if ($LASTEXITCODE -ne 0) { throw 'Embedded browser dependency setup failed. Local monitoring still works.' }
Write-Output 'Browser dependency ready. Microsoft Edge WebView2 runtime is also required. Reopen Sentinel; sign in on its embedded ChatGPT page.'

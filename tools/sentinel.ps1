param([switch]$Background)
$ErrorActionPreference = 'Stop'
$bundledPython = Join-Path $env:USERPROFILE '.cache/codex-runtimes/codex-primary-runtime/dependencies/python/pythonw.exe'
$pythonExecutable = if (Test-Path -LiteralPath $bundledPython) { $bundledPython } else { (Get-Command pythonw -ErrorAction Stop).Source }
$scriptPath = Join-Path $PSScriptRoot 'sentinel.py'
$launchArguments = @('"' + $scriptPath + '"')
if ($Background) { $launchArguments += '--background' }
# This is the visible interactive app requested by the user, not a background console helper.
Start-Process -FilePath $pythonExecutable -ArgumentList $launchArguments -WindowStyle Normal

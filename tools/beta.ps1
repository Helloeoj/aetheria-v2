param([ValidateSet('start','stop','status')][string]$Action = 'status')
$ErrorActionPreference = 'Stop'
$betaPython = Join-Path $env:LOCALAPPDATA 'Aetheria/online/venv/Scripts/python.exe'
& $betaPython (Join-Path $PSScriptRoot 'beta_ops.py') $Action
exit $LASTEXITCODE

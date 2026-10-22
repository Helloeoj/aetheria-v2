param([ValidateSet('start','run')][string]$Command = 'start', [int]$Port = 8765)
$ErrorActionPreference = 'Stop'
$bundled = Join-Path $env:USERPROFILE '.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe'
$pythonPath = if (Test-Path -LiteralPath $bundled) { $bundled } else { (& py -c 'import sys; print(sys.executable)').Trim() }
if ($Command -eq 'start') {
    $probe = New-Object System.Net.Sockets.TcpClient
    try {
        $connection = $probe.ConnectAsync('127.0.0.1', $Port)
        if ($connection.Wait(350) -and $probe.Connected) { exit 0 }
    } catch { } finally { $probe.Dispose() }
}
& $pythonPath -c 'import importlib.util,sys; sys.exit(0 if importlib.util.find_spec("websockets") else 1)'
if ($LASTEXITCODE -ne 0) {
    & $pythonPath -m pip install -r (Join-Path $PSScriptRoot 'social-requirements.txt')
    if ($LASTEXITCODE -ne 0) { throw 'Could not install the chat server dependency.' }
}
$serverScript = Join-Path $PSScriptRoot 'social_server.py'
if ($Command -eq 'run') {
    & $pythonPath $serverScript --port $Port
    exit $LASTEXITCODE
}
$outputFolder = Join-Path $env:LOCALAPPDATA 'Aetheria'
New-Item -ItemType Directory -Path $outputFolder -Force | Out-Null
Start-Process -FilePath $pythonPath -WindowStyle Hidden -ArgumentList @('"' + $serverScript + '"', '--port', "$Port") -RedirectStandardOutput (Join-Path $outputFolder 'chat-server.log') -RedirectStandardError (Join-Path $outputFolder 'chat-server-error.log')

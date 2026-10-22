param([ValidateSet('gui','start','stop','status','backup','build','logs')][string]$Action = 'gui')
$ErrorActionPreference = 'Stop'
$serverRepo = Split-Path -Parent $PSScriptRoot
$serverData = Join-Path $env:LOCALAPPDATA 'Aetheria/online'
if ($Action -eq 'gui') { & (Join-Path $PSScriptRoot 'server_panel.ps1'); exit }
if ($Action -eq 'logs') {
    Start-Process explorer.exe -ArgumentList ('"' + $serverData + '"')
    Write-Output 'Opened the local server log folder.'
    exit
}
if ($Action -in @('start','stop')) { & (Join-Path $PSScriptRoot 'online.ps1') $Action; exit $LASTEXITCODE }
if ($Action -eq 'status') {
    & (Join-Path $PSScriptRoot 'online.ps1') status
    $worldResult = $LASTEXITCODE
    & (Join-Path $PSScriptRoot 'accounts.ps1') status
    if (Test-Path -LiteralPath (Join-Path $serverData 'server-build.json')) {
        $serverBuild = Get-Content -LiteralPath (Join-Path $serverData 'server-build.json') -Raw | ConvertFrom-Json
        Write-Output 'Dedicated server build available.'
        if ($worldResult -eq 0) {
            $serverReady = Get-Content -LiteralPath (Join-Path $serverData 'world-ready.json') -Raw | ConvertFrom-Json
            $serverRunning = Get-CimInstance Win32_Process -Filter "ProcessId=$($serverReady.pid)"
            if ($serverRunning.ExecutablePath -eq $serverBuild.exe) { Write-Output 'Running the latest dedicated export.' }
            else { Write-Output 'Save / Stop, then Start to activate the latest dedicated export.' }
        }
    }
    exit $worldResult
}
$serverPython = Join-Path $serverData 'venv/Scripts/python.exe'
if (-not (Test-Path -LiteralPath $serverPython)) { throw 'Start the local account service before building or backing up.' }
if ($Action -eq 'backup') {
    & $serverPython (Join-Path $PSScriptRoot 'server_ops.py') backup
    exit $LASTEXITCODE
}
$serverGodot = $env:GODOT
if (-not $serverGodot) {
    $serverDetected = Get-Command godot -ErrorAction SilentlyContinue
    if ($serverDetected) { $serverGodot = $serverDetected.Source }
}
if (-not $serverGodot) {
    $serverDetected = Get-ChildItem -LiteralPath (Join-Path $env:USERPROFILE 'Downloads/Godot') -Filter '*4.5.1*console.exe' | Select-Object -First 1
    if ($serverDetected) { $serverGodot = $serverDetected.FullName }
}
if (-not $serverGodot) { throw 'Set GODOT to the installed Godot 4.5.1 console executable.' }
& $serverPython (Join-Path $PSScriptRoot 'server_ops.py') build --godot $serverGodot
if ($LASTEXITCODE -eq 0) { Write-Output 'Build ready. Save / Stop, then Start to activate it.' }
exit $LASTEXITCODE

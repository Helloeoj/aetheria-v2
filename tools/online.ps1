param([ValidateSet('start','stop','status')][string]$Action = 'status')
$ErrorActionPreference = 'Stop'
$onlineRepo = Split-Path -Parent $PSScriptRoot
$onlineData = Join-Path $env:LOCALAPPDATA 'Aetheria/online'
$onlineReady = Join-Path $onlineData 'world-ready.json'
$onlineStop = Join-Path $onlineData 'world-stop.request'

function Get-WorldProcess {
    if (-not (Test-Path -LiteralPath $onlineReady)) { return $null }
    try {
        $record = Get-Content -LiteralPath $onlineReady -Raw | ConvertFrom-Json
        $candidate = Get-CimInstance Win32_Process -Filter "ProcessId=$($record.pid)" -ErrorAction SilentlyContinue
        if ($candidate -and $candidate.CommandLine -like '*--world-server*' -and $candidate.CommandLine.Contains($onlineRepo)) { return $candidate }
    } catch { }
    return $null
}

if ($Action -eq 'status') {
    $world = Get-WorldProcess
    if ($world) {
        $record = Get-Content -LiteralPath $onlineReady -Raw | ConvertFrom-Json
        Write-Output "World $($record.world_id) ready on loopback:$($record.port); configured capacity $($record.max_players)."
        exit 0
    }
    Write-Output 'World stopped.'
    exit 1
}
if ($Action -eq 'stop') {
    if (Get-WorldProcess) {
        [System.IO.File]::WriteAllText($onlineStop, 'save-and-stop')
        $deadline = [DateTime]::UtcNow.AddSeconds(30)
        while ((Get-WorldProcess) -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 200 }
        if (Get-WorldProcess) { throw 'The world is still finalizing saves. It was not force-stopped.' }
    }
    Write-Output 'World stopped after saving. Account storage remains available.'
    exit 0
}
if (Get-WorldProcess) { & $PSCommandPath status; exit $LASTEXITCODE }
& (Join-Path $PSScriptRoot 'accounts.ps1') start
if ($LASTEXITCODE) { throw 'Account service failed to start.' }
New-Item -ItemType Directory -Path $onlineData -Force | Out-Null
Remove-Item -LiteralPath $onlineReady -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $onlineStop -Force -ErrorAction SilentlyContinue
$onlineGodot = $env:GODOT
if (-not $onlineGodot) {
    $detected = Get-Command godot -ErrorAction SilentlyContinue
    if ($detected) { $onlineGodot = $detected.Source }
}
if (-not $onlineGodot) {
    $downloadFolder = Join-Path $env:USERPROFILE 'Downloads/Godot'
    $detected = Get-ChildItem -LiteralPath $downloadFolder -Filter '*4.5.1*console.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($detected) { $onlineGodot = $detected.FullName }
}
if (-not $onlineGodot -or -not (Test-Path -LiteralPath $onlineGodot)) { throw 'Set GODOT to the installed Godot 4.5.1 console executable.' }
$onlineArguments = @('--headless', '--path', ('"' + (Join-Path $onlineRepo 'godot_client') + '"'), 'res://scenes/network/WorldServer.tscn', '--log-file', ('"' + (Join-Path $onlineData 'world.log') + '"'), '--', '--world-server', '--social-no-auto')
Start-Process -FilePath $onlineGodot -ArgumentList $onlineArguments -WindowStyle Hidden | Out-Null
$deadline = [DateTime]::UtcNow.AddSeconds(60)
while ([DateTime]::UtcNow -lt $deadline) {
    if (Get-WorldProcess) { & $PSCommandPath status; exit $LASTEXITCODE }
    Start-Sleep -Milliseconds 250
}
throw "World startup did not complete. Inspect the private world.log in $onlineData."

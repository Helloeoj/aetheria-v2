param(
    [Parameter(Mandatory=$true)][string]$Godot,
    [string]$EvidenceDirectory = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), 'aetheria-grid-' + [guid]::NewGuid().ToString('N'))
)
$ErrorActionPreference = 'Stop'
$projectPath = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../godot_client')).Path
$enginePath = (Resolve-Path -LiteralPath $Godot).Path
New-Item -ItemType Directory -Force -Path $EvidenceDirectory | Out-Null
$cases = @(
    @{Name='editor'; Args='--editor --quit'},
    @{Name='grid-unit'; Args='--script res://scripts/dev_tools/hidden_grid_unit.gd'},
    @{Name='grid-maps'; Args='--script res://scripts/dev_tools/hidden_grid_maps.gd'},
    @{Name='movement-server'; Args='res://scenes/dev_tools/movement_server_smoke.tscn'},
    @{Name='movement-presentation'; Args='--script res://scripts/dev_tools/movement_presentation_smoke.gd'},
    @{Name='interactions'; Args='--script res://scripts/dev_tools/world_interaction_smoke.gd'},
    @{Name='combat'; Args='res://scenes/dev_tools/bronze_combat_smoke.tscn'},
    @{Name='authority'; Args='res://scenes/dev_tools/region_authority_smoke.tscn'},
    @{Name='freeze'; Args='res://scenes/dev_tools/region_freeze_smoke.tscn'},
    @{Name='travel'; Args='res://scenes/dev_tools/scene_travel_unit.tscn'},
    @{Name='online-travel'; Args='res://scenes/dev_tools/online_region_travel_smoke.tscn'},
    @{Name='tavern'; Args='res://scenes/dev_tools/tavern_integration.tscn'},
    @{Name='startup'; Args='--quit-after 120'}
)
if (Test-Path -LiteralPath (Join-Path $projectPath 'scenes/dev_tools/catacombs_integration.tscn')) {
    $cases += @{Name='catacombs-local'; Args='res://scenes/dev_tools/catacombs_integration.tscn'}
}
$failed = @()
foreach ($case in $cases) {
    $stdoutPath = Join-Path $EvidenceDirectory ($case.Name + '.stdout.log')
    $stderrPath = Join-Path $EvidenceDirectory ($case.Name + '.stderr.log')
    $arguments = '--headless --path "' + $projectPath + '" ' + $case.Args
    $process = Start-Process -FilePath $enginePath -ArgumentList $arguments -PassThru -WindowStyle Hidden -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
    $finished = $process.WaitForExit(55000)
    if (-not $finished) {
        Stop-Process -Id $process.Id
        $failed += $case.Name
        Write-Output ('FAIL ' + $case.Name + ': timed out')
        continue
    }
    $process.Refresh()
    $output = (Get-Content -Raw -LiteralPath $stdoutPath) + (Get-Content -Raw -LiteralPath $stderrPath)
    if ($process.ExitCode -ne 0 -or $output -match '(?m)SCRIPT ERROR:|^ERROR:|FAIL\]|^FAIL:') {
        $failed += $case.Name
        Write-Output ('FAIL ' + $case.Name + ': exit ' + $process.ExitCode)
        Write-Output $output
    } else {
        Write-Output ('PASS ' + $case.Name)
    }
}
Write-Output ('Evidence: ' + $EvidenceDirectory)
Write-Output ('Grid validation: ' + $cases.Count + ' suites, ' + $failed.Count + ' failures')
if ($failed.Count -gt 0) { exit 1 }
exit 0

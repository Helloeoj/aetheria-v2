param(
    [Parameter(Position=0)][string]$Command = 'prepare',
    [Parameter(ValueFromRemainingArguments=$true)][string[]]$AdcArguments
)
$ErrorActionPreference = 'Stop'
$bundledPython = Join-Path $env:USERPROFILE '.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe'
$pythonExecutable = if (Test-Path -LiteralPath $bundledPython) { $bundledPython } else { (Get-Command python -ErrorAction Stop).Source }
$engineArguments = @()
if ($Command -in @('run', 'test')) {
    $enginePath = $env:GODOT
    if (-not $enginePath) {
        $runningEngine = Get-CimInstance Win32_Process | Where-Object { $_.Name -like 'Godot*.exe' -and $_.ExecutablePath } | Select-Object -First 1
        if ($runningEngine) { $enginePath = $runningEngine.ExecutablePath }
    }
    if (-not $enginePath) { throw 'Set $env:GODOT to your installed Godot executable, or open Godot first.' }
    $engineArguments = @('--godot', $enginePath)
}
$forwardArguments = @($AdcArguments)
if ($Command -eq 'run') {
    if ($forwardArguments.Count -gt 0 -and $forwardArguments[0] -eq '--') {
        $forwardArguments = @($forwardArguments | Select-Object -Skip 1)
    }
    $forwardArguments = @('--') + $forwardArguments
}
& $pythonExecutable (Join-Path $PSScriptRoot 'adc.py') @engineArguments $Command @forwardArguments
exit $LASTEXITCODE

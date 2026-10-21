# Creates a per-user desktop shortcut. Does not install services or enable login startup.
$ErrorActionPreference = 'Stop'
$runtimeFolder = Join-Path $env:USERPROFILE '.cache/codex-runtimes/codex-primary-runtime/dependencies/python'
$pythonExecutable = Join-Path $runtimeFolder 'python.exe'
$pythonWindowed = Join-Path $runtimeFolder 'pythonw.exe'
if (-not (Test-Path -LiteralPath $pythonWindowed)) {
    $pythonWindowed = (Get-Command pythonw -ErrorAction Stop).Source
    $pythonExecutable = Join-Path (Split-Path -Parent $pythonWindowed) 'python.exe'
}
$paths = (& $pythonExecutable (Join-Path $PSScriptRoot 'adc.py') paths) | ConvertFrom-Json
$iconPath = Join-Path $paths.storage 'companion/sentinel.ico'
& $pythonExecutable -c 'import sys; from pathlib import Path; sys.path.insert(0,sys.argv[1]); from sentinel_windows import make_icon; make_icon(Path(sys.argv[2]))' $PSScriptRoot $iconPath
if ($LASTEXITCODE -ne 0) { throw 'Could not prepare the Sentinel icon.' }
$desktopFolder = [Environment]::GetFolderPath('Desktop')
$shortcutPath = Join-Path $desktopFolder 'Aetheria Sentinel.lnk'
$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($shortcutPath)
if ((Test-Path -LiteralPath $shortcutPath) -and $shortcut.TargetPath -and $shortcut.TargetPath -ne $pythonWindowed) {
    throw 'A different application already owns the Aetheria Sentinel desktop shortcut.'
}
$shortcut.TargetPath = $pythonWindowed
$shortcut.Arguments = '"' + (Join-Path $PSScriptRoot 'sentinel.py') + '"'
$shortcut.WorkingDirectory = Split-Path -Parent $PSScriptRoot
$shortcut.Description = 'Aetheria Sentinel — independent local diagnostic companion'
$shortcut.IconLocation = $iconPath + ',0'
$shortcut.WindowStyle = 1
$shortcut.Save()
Write-Output $shortcutPath

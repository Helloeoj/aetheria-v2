param([ValidateSet('oauth','verify','update','play')][string]$Mode = 'verify')
$ErrorActionPreference = 'Stop'
$liveRepo = Split-Path -Parent $PSScriptRoot
$liveRuntime = Join-Path $env:LOCALAPPDATA 'Aetheria/online/beta-runtime'
$liveSources = @('Core.cs','LauncherService.cs','Program.cs','LiveCheck.cs') | ForEach-Object { Join-Path $liveRepo ('launcher/' + $_) }
$liveProbe = Join-Path $liveRuntime 'AetheriaLauncher.LiveCheck.exe'
& (Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319/csc.exe') /nologo /warnaserror+ /target:exe /platform:x64 /main:AetheriaLauncher.LiveCheck "/out:$liveProbe" /reference:System.Web.Extensions.dll /reference:System.Web.dll /reference:System.Windows.Forms.dll /reference:System.Drawing.dll $liveSources
if ($LASTEXITCODE) { throw 'Live launcher probe did not compile.' }
& $liveProbe ('--' + $Mode)
exit $LASTEXITCODE

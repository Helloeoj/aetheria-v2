[CmdletBinding()]
param(
    [string]$OutputDirectory = '',
    [string]$ConfigPath = '',
    [string]$ButlerPath = '',
    [switch]$Test,
    [switch]$RealDaemonTest
)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
if (!$OutputDirectory) { $OutputDirectory = Join-Path $repoRoot 'build/launcher' }
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
$compiler = Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
if (!(Test-Path -LiteralPath $compiler)) { throw '.NET Framework C# compiler is unavailable.' }
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$sourceRoot = Join-Path $repoRoot 'launcher'
$sources = @((Join-Path $sourceRoot 'Core.cs'), (Join-Path $sourceRoot 'LauncherService.cs'))
$references = @('/reference:System.Web.Extensions.dll', '/reference:System.Web.dll')
& $compiler /nologo /warnaserror+ /optimize+ /target:winexe /platform:x64 "/out:$OutputDirectory/AetheriaLauncher.exe" $references /reference:System.Windows.Forms.dll /reference:System.Drawing.dll $sources (Join-Path $sourceRoot 'Program.cs')
if ($LASTEXITCODE -ne 0) { throw 'Launcher compilation failed.' }
if (!$ButlerPath) { $ButlerPath = Join-Path $env:LOCALAPPDATA 'Aetheria/online/beta-runtime/butler/butler.exe' }
if ($ConfigPath) {
    $settings = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
    $uri = $null
    if ($settings.schema -ne 1 -or $settings.game_id -le 0 -or $settings.upload_id -le 0 -or !$settings.oauth_client_id -or $settings.executable -ne 'Aetheria.exe' -or $settings.download_bytes_per_second -ne 500000 -or ![Uri]::TryCreate($settings.account_url, [UriKind]::Absolute, [ref]$uri) -or $uri.Scheme -ne 'https' -or $uri.UserInfo -or $uri.Query -or $uri.Fragment) { throw 'Launcher config is incomplete or invalid; consumer itch.io setup is required.' }
    Copy-Item -LiteralPath $ConfigPath -Destination (Join-Path $OutputDirectory 'launcher.json') -Force
} else {
    Copy-Item -LiteralPath (Join-Path $sourceRoot 'launcher.example.json') -Destination (Join-Path $OutputDirectory 'launcher.json') -Force
    Write-Output 'Development bootstrap only: itch.io account/config integration is pending.'
}
if (Test-Path -LiteralPath $ButlerPath) {
    $butlerVersion = & $ButlerPath version
    if ($LASTEXITCODE -ne 0 -or $butlerVersion -notmatch '^v15\.32\.0,') { throw 'Only pinned butler v15.32.0 is supported.' }
    if ([IO.Path]::GetFullPath($ButlerPath) -ne (Join-Path $OutputDirectory 'butler.exe')) { Copy-Item -LiteralPath $ButlerPath -Destination (Join-Path $OutputDirectory 'butler.exe') -Force }
} else { throw 'Pinned bundled butler is missing; this script does not download dependencies.' }
Copy-Item -LiteralPath (Join-Path $repoRoot 'licenses/BUTLER-LICENSE.txt') -Destination (Join-Path $OutputDirectory 'BUTLER-LICENSE.txt') -Force
Copy-Item -LiteralPath (Join-Path $sourceRoot 'PLAYER-README.txt') -Destination (Join-Path $OutputDirectory 'README.txt') -Force
if ($Test -or $RealDaemonTest) {
    $testDirectory = Join-Path $repoRoot 'build/launcher-tests'
    New-Item -ItemType Directory -Path $testDirectory -Force | Out-Null
    $testPath = Join-Path $testDirectory 'AetheriaLauncher.Tests.exe'
    Copy-Item -LiteralPath (Join-Path $sourceRoot 'launcher.example.json') -Destination (Join-Path $testDirectory 'launcher.json') -Force
    & $compiler /nologo /warnaserror+ /target:exe /platform:x64 /main:AetheriaLauncher.LauncherTests "/out:$testPath" $references /reference:System.Windows.Forms.dll /reference:System.Drawing.dll $sources (Join-Path $sourceRoot 'Program.cs') (Join-Path $sourceRoot 'Tests.cs')
    if ($LASTEXITCODE -ne 0) { throw 'Launcher test compilation failed.' }
    if ($RealDaemonTest) { & $testPath --butler (Join-Path $OutputDirectory 'butler.exe') } else { & $testPath }
    if ($LASTEXITCODE -ne 0) { throw 'Launcher tests failed.' }
}
Write-Output "Launcher bootstrap built: $OutputDirectory"

param([switch]$SmokeTest)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
$serverPanel = New-Object System.Windows.Forms.Form
$serverPanel.Text = 'Aetheria Server'
$serverPanel.Size = New-Object System.Drawing.Size(690, 410)
$serverPanel.StartPosition = 'CenterScreen'
$serverPanel.MinimumSize = $serverPanel.Size
$serverDescription = New-Object System.Windows.Forms.Label
$serverDescription.Text = 'Local server controls. Closing this window leaves the server running.'
$serverDescription.SetBounds(16, 14, 640, 26)
$serverPanel.Controls.Add($serverDescription)
$serverOutput = New-Object System.Windows.Forms.TextBox
$serverOutput.Multiline = $true
$serverOutput.ReadOnly = $true
$serverOutput.ScrollBars = 'Vertical'
$serverOutput.SetBounds(16, 96, 640, 250)
$serverOutput.Anchor = 'Top,Bottom,Left,Right'
$serverPanel.Controls.Add($serverOutput)
$script:serverWorker = $null
$script:serverOperation = ''
$script:serverButtons = @()
function Invoke-ServerAction([string]$operation) {
    if ($script:serverWorker) { return }
    $script:serverOperation = $operation
    $serverOutput.Text = "$operation in progress..."
    foreach ($button in $script:serverButtons) { $button.Enabled = $false }
    $info = New-Object System.Diagnostics.ProcessStartInfo
    $info.FileName = 'powershell.exe'
    $info.Arguments = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + (Join-Path $PSScriptRoot 'server.ps1') + '" ' + $operation
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $script:serverWorker = [System.Diagnostics.Process]::Start($info)
    $script:serverStdout = $script:serverWorker.StandardOutput.ReadToEndAsync()
    $script:serverStderr = $script:serverWorker.StandardError.ReadToEndAsync()
}
$left = 16
foreach ($operation in @('start','stop','status','backup','logs','build')) {
    $button = New-Object System.Windows.Forms.Button
    $button.Text = @{start='Start';stop='Save / Stop';status='Refresh';backup='Backup';logs='Log Folder';build='Build'}[$operation]
    $button.Tag = $operation
    $button.SetBounds($left, 48, 100, 34)
    $button.Add_Click({ Invoke-ServerAction $this.Tag })
    $serverPanel.Controls.Add($button)
    $script:serverButtons += $button
    $left += 108
}
$serverTimer = New-Object System.Windows.Forms.Timer
$serverTimer.Interval = 250
$serverTimer.Add_Tick({
    if ($script:serverWorker -and $script:serverWorker.HasExited -and $script:serverStdout.IsCompleted -and $script:serverStderr.IsCompleted) {
        $serverOutput.Text = $script:serverStdout.Result + $script:serverStderr.Result
        if ($script:serverWorker.ExitCode -ne 0 -and $script:serverOperation -ne 'status') { $serverOutput.AppendText("`r`nAction did not complete successfully. Review the details above.") }
        $script:serverWorker.Dispose()
        $script:serverWorker = $null
        foreach ($button in $script:serverButtons) { $button.Enabled = $true }
        if ($SmokeTest) { $serverPanel.Close() }
    }
})
$serverPanel.Add_Shown({ Invoke-ServerAction 'status'; $serverTimer.Start() })
$serverPanel.Add_FormClosing({
    if ($script:serverWorker) {
        $_.Cancel = $true
        $serverDescription.Text = 'Wait for the current action to finish before closing this window.'
    }
})
$null = $serverPanel.ShowDialog()
$serverTimer.Dispose()
$serverPanel.Dispose()

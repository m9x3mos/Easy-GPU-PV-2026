$ErrorActionPreference = 'Continue'

# Base capability names to remove (matched on the part before '~').
$selectors = @(
    'Print.Fax.Scan'
    'Browser.InternetExplorer'
    'MathRecognizer'
    'OneCoreUAP.OneSync'
    'App.StepsRecorder'
    'Media.WindowsMediaPlayer'
    'Microsoft.Windows.WordPad'
)

$timeoutSec = 60
$removed  = 0
$timedOut = 0
$failed   = 0

$installed = @(Get-WindowsCapability -Online | Where-Object { $_.State -ne 'NotPresent' -and $_.State -ne 'Removed' })
$toRemove  = @($installed | Where-Object { $selectors -contains (($_.Name -split '~')[0]) })

Write-Host ("Found {0} capability(ies) to remove" -f $toRemove.Count) -ForegroundColor Cyan

foreach ($cap in $toRemove) {
    $name = $cap.Name
    Write-Host "Removing capability: $name" -ForegroundColor Cyan
    $proc = $null
    try {
        $proc = Start-Process -FilePath 'dism.exe' `
            -ArgumentList '/Online', '/Delete-Capability', "/CapabilityName:$name" `
            -PassThru -WindowStyle Hidden
        $exited = $proc.WaitForExit($timeoutSec * 1000)
        if (-not $exited) {
            Write-Host "  TIMEOUT after ${timeoutSec}s - killing and skipping $name" -ForegroundColor Yellow
            try { $proc.Kill() } catch {}
            $timedOut++
            continue
        }
        if ($proc.ExitCode -eq 0) {
            Write-Host "  removed: $name" -ForegroundColor Green
            $removed++
        } else {
            Write-Host "  skipped (not present / exit $($proc.ExitCode)): $name" -ForegroundColor DarkGray
        }
    }
    catch {
        Write-Host "  error removing $name : $($_.Exception.Message)" -ForegroundColor DarkGray
        $failed++
    }
}

Write-Host ''
Write-Host ("RemoveCapabilities done: {0} removed, {1} timed out, {2} failed" -f $removed, $timedOut, $failed) -ForegroundColor White

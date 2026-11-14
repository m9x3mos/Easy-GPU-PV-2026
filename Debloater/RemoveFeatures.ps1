$ErrorActionPreference = 'Continue'

# Optional features to disable (matched on FeatureName).
$selectors = @(
    'Recall'
)

$timeoutSec = 90
$removed  = 0
$timedOut = 0
$failed   = 0

$installed = @(Get-WindowsOptionalFeature -Online | Where-Object { $_.State -ne 'Disabled' -and $_.State -ne 'DisabledWithPayloadRemoved' })
$toRemove  = @($installed | Where-Object { $selectors -contains $_.FeatureName })

Write-Host ("Found {0} feature(s) to disable" -f $toRemove.Count) -ForegroundColor Cyan

foreach ($feat in $toRemove) {
    $name = $feat.FeatureName
    Write-Host "Disabling feature: $name" -ForegroundColor Cyan
    $proc = $null
    try {
        $proc = Start-Process -FilePath 'dism.exe' `
            -ArgumentList '/Online', '/Disable-Feature', "/FeatureName:$name", '/Remove', '/NoRestart' `
            -PassThru -WindowStyle Hidden
        $exited = $proc.WaitForExit($timeoutSec * 1000)
        if (-not $exited) {
            Write-Host "  TIMEOUT after ${timeoutSec}s - killing and skipping $name" -ForegroundColor Yellow
            try { $proc.Kill() } catch {}
            $timedOut++
            continue
        }
        if ($proc.ExitCode -eq 0) {
            Write-Host "  disabled: $name" -ForegroundColor Green
            $removed++
        } else {
            Write-Host "  skipped (not present / exit $($proc.ExitCode)): $name" -ForegroundColor DarkGray
        }
    }
    catch {
        Write-Host "  error disabling $name : $($_.Exception.Message)" -ForegroundColor DarkGray
        $failed++
    }
}

Write-Host ''
Write-Host ("RemoveFeatures done: {0} disabled, {1} timed out, {2} failed" -f $removed, $timedOut, $failed) -ForegroundColor White

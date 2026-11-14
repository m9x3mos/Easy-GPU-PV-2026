$ErrorActionPreference = 'Continue'

# Provisioned Appx packages to remove. Order does not matter.
$packages = @(
    'Microsoft.Windows.Cortana'
    'Microsoft.MicrosoftStickerPack'
    'Microsoft.GamingApp'
    'Microsoft.GetHelp'
    'Microsoft.MSPaint'
    'Microsoft.OneDrive'
    'Microsoft.Print3D'
    'Microsoft.Windows.Phones'
    'Microsoft.WindowsMaps'
    'Microsoft.WindowsSoundRecorder'
    'Microsoft.ZuneMusic'
    'Microsoft.ZuneVideo'
    'Microsoft.People'
    'Microsoft.3DBuilder'
    'Microsoft.BingNews'
    'Microsoft.3DPrintProvider'
    'Microsoft.MixedReality.Portal'
    'Microsoft.WindowsFeedbackHub'
    'Microsoft.Windows.Copilot'
) | Select-Object -Unique

# Remove each package in its own dism.exe process with a hard timeout, so a
# single stuck package is killed and skipped instead of hanging the whole run.
$timeoutSec = 60
$removed  = 0
$timedOut = 0
$failed   = 0

foreach ($pkg in $packages) {
    Write-Host "Removing provisioned package: $pkg" -ForegroundColor Cyan
    $proc = $null
    try {
        $proc = Start-Process -FilePath 'dism.exe' `
            -ArgumentList '/Online', '/Remove-ProvisionedAppxPackage', "/PackageName:$pkg" `
            -PassThru -WindowStyle Hidden
        $exited = $proc.WaitForExit($timeoutSec * 1000)
        if (-not $exited) {
            Write-Host "  TIMEOUT after ${timeoutSec}s - killing and skipping $pkg" -ForegroundColor Yellow
            try { $proc.Kill() } catch {}
            $timedOut++
            continue
        }
        if ($proc.ExitCode -eq 0) {
            Write-Host "  removed: $pkg" -ForegroundColor Green
            $removed++
        } else {
            Write-Host "  skipped (not present / exit $($proc.ExitCode)): $pkg" -ForegroundColor DarkGray
        }
    }
    catch {
        Write-Host "  error removing $pkg : $($_.Exception.Message)" -ForegroundColor DarkGray
        $failed++
    }
}

Write-Host ''
Write-Host ("RemovePackages done: {0} removed, {1} timed out, {2} failed" -f $removed, $timedOut, $failed) -ForegroundColor White

Write-Host 'Applying Start menu pins ...' -ForegroundColor Cyan
& 'C:\Windows\Setup\Scripts\SetStartPins.ps1'

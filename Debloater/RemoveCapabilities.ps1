$ErrorActionPreference = 'Continue'

# Optional features / capabilities to remove. Order does not matter.
$capabilities = @(
    'App.Support.QuickAssist'
    'AppApp'
    'LightingControl'
    'Media.PTV'
    'Microsoft.Windows.FaxAndScan'
    'Microsoft.Windows.MSPaint'
    'Microsoft.Windows.Notepad'
    'Microsoft.Windows.PicturePal'
    'Microsoft.Windows.Recall'
    'Microsoft.Windows.Scan'
    'Microsoft.Windows.Speech'
    'Microsoft.Windows.WordPad'
    'Print.Basics'
    'PrintSupport'
    'SpeechRecognition'
    'Windows.Media.Playback'
    'WindowsNotepad'
    'XPSViewer'
) | Select-Object -Unique

# --- DISM retry helper (self-contained, no external deps) ---
# Runs one DISM /Online operation with a hard timeout. If it times out, it is
# killed and retried (with a backoff) up to $MaxAttempts times. If it still
# cannot finish, the item is skipped (logged) so the overall chain always
# completes instead of hanging forever on a locked DISM engine.
function Invoke-DismItem {
    param([string[]]$DismArgs, [string]$Label, [int]$TimeoutSec = 180, [int]$MaxAttempts = 3)
    $backoff = @(30, 60)
    for ($a = 1; $a -le $MaxAttempts; $a++) {
        $p = $null
        try {
            $p = Start-Process -FilePath 'dism.exe' -ArgumentList $DismArgs -PassThru -WindowStyle Hidden
            if (-not $p.WaitForExit($TimeoutSec * 1000)) {
                Write-Host "  TIMEOUT after ${TimeoutSec}s (attempt $a/$MaxAttempts): $Label" -ForegroundColor Yellow
                try { $p.Kill() } catch {}
            }
            elseif ($p.ExitCode -eq 0) {
                Write-Host "  removed: $Label" -ForegroundColor Green
                return $true
            }
            else {
                Write-Host "  skipped (not present / exit $($p.ExitCode)): $Label" -ForegroundColor DarkGray
                return $true
            }
        }
        catch {
            Write-Host "  error: $($_.Exception.Message)" -ForegroundColor DarkGray
            return $true
        }
        if ($a -lt $MaxAttempts) {
            $w = $backoff[[Math]::Min($a - 1, $backoff.Count - 1)]
            Write-Host "  retrying in ${w}s ..." -ForegroundColor Yellow
            Start-Sleep -Seconds $w
        }
    }
    Write-Host "  SKIPPED after $MaxAttempts attempts: $Label" -ForegroundColor Red
    return $false
}
# --- end helper ---

$removed = 0
$skipped = 0

foreach ($name in $capabilities) {
    Write-Host "Removing capability: $name" -ForegroundColor Cyan
    if (Invoke-DismItem -DismArgs @('/Online', '/Delete-Capability', "/CapabilityName:$name") -Label $name) {
        $removed++
    }
    else {
        $skipped++
    }
}

Write-Host ''
Write-Host ("RemoveCapabilities done: {0} removed, {1} skipped after retries" -f $removed, $skipped) -ForegroundColor White

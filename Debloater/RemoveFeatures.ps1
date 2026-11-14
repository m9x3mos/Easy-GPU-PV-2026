$ErrorActionPreference = 'Continue'

# Optional Windows features to disable (and their payload removed).
$features = @(
    'WindowsMediaPlayer'
    'WindowsNFS'
    'WCF-HTTP-Activation45'
    'WMI-Basic'
    'WMI-Driver-Extensions'
    'WFAS-HTTP-Activation45'
    'WFAS-NetTcpHttp45'
    'WFAS-ServiceModel45'
    'Windows-DEF'
    'Windows-DEF-R'
    'Windows-IdentityExtensions'
    'Windows-IdentityExtensions-R'
    'Windows-MinorUI'
    'Windows-Printers'
    'Windows-Printing-Base'
    'Windows-Printing-Basic-Features'
    'Windows-Printing- LPB'
    'Windows-Printing-Routing-Features'
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

foreach ($name in $features) {
    Write-Host "Disabling feature: $name" -ForegroundColor Cyan
    if (Invoke-DismItem -DismArgs @('/Online', '/Disable-Feature', "/FeatureName:$name", '/Remove', '/NoRestart') -Label $name) {
        $removed++
    }
    else {
        $skipped++
    }
}

Write-Host ''
Write-Host ("RemoveFeatures done: {0} disabled, {1} skipped after retries" -f $removed, $skipped) -ForegroundColor White

# EasyGPU Debloat orchestrator.
# Runs the extracted debloat chain once, in the correct order, with logging.
# Guarded by a completion flag so it never re-runs (and never reboot-loops).
$ErrorActionPreference = 'Continue'

$pkgDir    = 'C:\ProgramData\Easy-GPU-P'
$flagPath  = Join-Path $pkgDir 'debloat-complete.flag'
$scriptDir = 'C:\Windows\Setup\Scripts'
$logFile   = Join-Path $pkgDir 'debloat.log'

function Write-Log {
    param([string]$Message)
    $line = ('{0}  {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message)
    Write-Output $line
    try {
        if (-not (Test-Path -LiteralPath $pkgDir)) { New-Item -Path $pkgDir -ItemType Directory -Force | Out-Null }
        Add-Content -LiteralPath $logFile -Value $line -Encoding UTF8
    } catch { }
}

# One-time guard: if the core debloat already completed, do nothing.
if (Test-Path -LiteralPath $flagPath) {
    Write-Log 'Debloat already completed (flag present). Skipping.'
    return
}

Write-Log '=== EasyGPU Debloat starting ==='

# 1) Machine-wide debloat: removes Appx packages, capabilities, optional features,
#    and applies machine policies (OneDrive/Outlook/Copilot, Edge, RDP, etc.).
Write-Log 'Running Specialize.ps1 ...'
try { & (Join-Path $scriptDir 'Specialize.ps1') }
catch { Write-Log ('Specialize.ps1 ERROR: ' + $_.Exception.Message) }

# 2) Default-user template configuration. The hive must be mounted at HKU\DefaultUser
#    because DefaultUser.ps1 targets that path.
$loaded = $false
Write-Log 'Loading HKU\DefaultUser hive ...'
$loadResult = reg.exe load 'HKU\DefaultUser' 'C:\Users\Default\NTUSER.DAT' 2>&1
if ($LASTEXITCODE -eq 0) { $loaded = $true; Write-Log 'Default user hive loaded.' }
else { Write-Log ('Hive load result (may already be available): ' + ($loadResult -join ' ')) }

try { & (Join-Path $scriptDir 'DefaultUser.ps1') }
catch { Write-Log ('DefaultUser.ps1 ERROR: ' + $_.Exception.Message) }

if ($loaded) {
    reg.exe unload 'HKU\DefaultUser' 2>&1 | Out-Null
    Write-Log 'Default user hive unloaded.'
}

# 3) Per-user configuration: removes the user's Copilot package, applies the user's
#    dark theme and explorer settings, then restarts explorer.
Write-Log 'Running UserOnce.ps1 ...'
try { & (Join-Path $scriptDir 'UserOnce.ps1') }
catch { Write-Log ('UserOnce.ps1 ERROR: ' + $_.Exception.Message) }

# Mark the core debloat complete BEFORE the finalize/reboot step so that a reboot
# can never cause this to run again (no reboot loop).
try { Set-Content -LiteralPath $flagPath -Value ((Get-Date).ToString('o')) -Encoding UTF8 }
catch { Write-Log 'WARNING: could not write completion flag.' }
Write-Log 'Core debloat complete. Completion flag written.'

# 4) Finalize: disable autologon count, remove Windows.old, apply dark theme,
#    clean up, then perform the one-time reboot.
Write-Log 'Running FirstLogon.ps1 (finalize + one-time reboot) ...'
try { & (Join-Path $scriptDir 'FirstLogon.ps1') }
catch { Write-Log ('FirstLogon.ps1 ERROR: ' + $_.Exception.Message) }

Write-Log '=== EasyGPU Debloat finished ==='

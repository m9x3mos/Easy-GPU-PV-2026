# EasyGPU Debloat orchestrator.
# Runs the extracted debloat chain once, in the correct order, with logging.
# Guarded by a completion flag so it never re-runs (and never reboot-loops).
$ErrorActionPreference = 'Continue'

$pkgDir      = 'C:\ProgramData\Easy-GPU-P'
$flagPath    = Join-Path $pkgDir 'debloat-complete.flag'
$preFlagPath = Join-Path $pkgDir 'pre-first-logon.flag'
$scriptDir   = 'C:\Windows\Setup\Scripts'
$logFile     = 'C:\Windows\Setup\Scripts\debloat.log'

function Write-Log {
    param([string]$Message)
    $line = ('{0}  {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message)
    Write-Output $line
    try {
        $logDir = Split-Path -Parent $logFile
        if ($logDir -and -not (Test-Path -LiteralPath $logDir)) { New-Item -Path $logDir -ItemType Directory -Force | Out-Null }
        Add-Content -LiteralPath $logFile -Value $line -Encoding UTF8
    } catch {
        Write-Output ('LOG WRITE ERROR: ' + $_.Exception.Message)
    }
}

# One-time guard: if the core debloat already completed, do nothing.
if (Test-Path -LiteralPath $flagPath) {
    Write-Log 'Debloat already completed (flag present). Skipping.'
    return
}

Write-Log '=== EasyGPU Debloat starting ==='

# Log the execution context. This makes HKCU / session problems (for example a
# non-interactive S4U task) obvious in the log.
try {
    $identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    $elevated  = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    $sessionId = (Get-Process -Id $PID -ErrorAction SilentlyContinue).SessionId
    Write-Log ('Context: user={0}; session={1}; elevated={2}; powershell={3}; os={4}' -f `
        $identity.Name, $sessionId, $elevated, $PSVersionTable.PSVersion.ToString(), [Environment]::OSVersion.VersionString)
}
catch {
    Write-Log ('Context: could not collect environment information: ' + $_.Exception.Message)
}

if (Test-Path -LiteralPath $preFlagPath) {
    Write-Log 'Pre-first-logon phase flag present.'
}
else {
    Write-Log 'WARNING: pre-first-logon phase flag not found. The Setup specialize-pass debloat may not have run; continuing with the first-logon debloat.'
}

# 1) Machine-wide debloat: removes Appx packages, capabilities, optional features,
#    and applies machine policies (OneDrive/Outlook/Copilot, Edge, RDP, etc.).
Write-Log 'Running Specialize.ps1 ...'
try { & (Join-Path $scriptDir 'Specialize.ps1') }
catch { Write-Log ('Specialize.ps1 ERROR: ' + $_.Exception.Message) }

# 2) Default-profile template. DefaultUser.ps1 loads and unloads
#    C:\Users\Default\NTUSER.DAT itself, so no manual reg load is needed here.
Write-Log 'Running DefaultUser.ps1 ...'
try { & (Join-Path $scriptDir 'DefaultUser.ps1') }
catch { Write-Log ('DefaultUser.ps1 ERROR: ' + $_.Exception.Message) }

# 3) Per-user configuration: removes the user's Copilot/OneDrive packages, sets
#    the taskbar to left-aligned, applies the dark theme, then restarts Explorer.
Write-Log 'Running UserOnce.ps1 ...'
try { & (Join-Path $scriptDir 'UserOnce.ps1') }
catch { Write-Log ('UserOnce.ps1 ERROR: ' + $_.Exception.Message) }

# 3a) Fallback: unlock the Start layout directly in case the event-driven
#     UnlockStartLayout task did not fire.
$unlockScript = Join-Path $scriptDir 'UnlockStartLayout.vbs'
if (Test-Path -LiteralPath $unlockScript) {
    Write-Log 'Running UnlockStartLayout.vbs (fallback) ...'
    try {
        $unlockOutput = & cscript.exe //nologo $unlockScript 2>&1
        foreach ($line in $unlockOutput) { Write-Log ('UNLOCK: ' + $line) }
    }
    catch {
        Write-Log ('UnlockStartLayout.vbs ERROR: ' + $_.Exception.Message)
    }
}
else {
    Write-Log 'WARNING: UnlockStartLayout.vbs not found; skipping Start layout unlock.'
}

# 3b) Verify that the important results actually applied.
Write-Log 'Running Test-Debloat.ps1 (verification) ...'
$verifyScript = Join-Path $scriptDir 'Test-Debloat.ps1'
if (Test-Path -LiteralPath $verifyScript) {
    try {
        $verifyOutput = & $verifyScript 2>&1
        foreach ($line in $verifyOutput) { Write-Log ('VERIFY: ' + $line) }
    }
    catch {
        Write-Log ('Test-Debloat.ps1 ERROR: ' + $_.Exception.Message)
    }
}
else {
    Write-Log 'WARNING: Test-Debloat.ps1 not found; skipping verification.'
}

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

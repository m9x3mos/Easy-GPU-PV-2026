param(
    [switch]$PatternsOnly
)

$ErrorActionPreference = 'Continue'

# Provisioned Appx packages to remove. Order does not matter.
# OneDrive and Copilot are handled by the wildcard patterns below because their
# package identities differ between Windows builds (for example
# Microsoft.OneDriveSync and Microsoft.Copilot on Windows 11 25H2). The same is
# true for several bundled apps (Teams, Outlook, WhatsApp, LinkedIn, Adobe
# Express), whose exact identity can change between images.
#
# The Xbox app (Microsoft.GamingApp) is intentionally NOT removed so it can
# still be installed from the Microsoft Store.
$packages = @(
    'Microsoft.Windows.Cortana'
    'Microsoft.MicrosoftStickerPack'
    'Microsoft.GetHelp'
    'Microsoft.MSPaint'
    'Microsoft.Print3D'
    'Microsoft.Windows.Phones'
    'Microsoft.WindowsMaps'
    'Microsoft.WindowsSoundRecorder'
    'Microsoft.ZuneMusic'
    'Microsoft.ZuneVideo'
    'Microsoft.People'
    'Microsoft.3DBuilder'
    'Microsoft.BingNews'
    'Microsoft.BingWeather'
    'Microsoft.3DPrintProvider'
    'Microsoft.MixedReality.Portal'
    'Microsoft.WindowsFeedbackHub'
    'MicrosoftTeams'
    'MSTeams'
    'Microsoft.Todos'
    'Microsoft.OutlookForWindows'
    'microsoft.windowscommunicationsapps'
    'Microsoft.YourPhone'
    'Microsoft.MicrosoftSolitaireCollection'
    '5319275A.WhatsAppDesktop'
    'Microsoft.MicrosoftOfficeHub'
    'Microsoft.Office.ActionsServer'
    'Microsoft.OfficePushNotificationUtility'
    'Microsoft.Office.OneNoteVirtualPrinter'
    '7EE7776C.LinkedInforWindows'
    'Adobe.Express'
    'MicrosoftCorporationII.MicrosoftFamily'
    'Clipchamp.Clipchamp'
) | Select-Object -Unique

# Package-name patterns that are always removed, in both debloat phases. These
# match provisioned and installed packages regardless of the exact identity
# name used by the current Windows build.
#
# *WebExperience* is the "Windows Web Experience Pack"
# (MicrosoftWindows.Client.WebExperience), the package that provides the
# Widgets board and its taskbar entry point. Removing it removes Widgets.
$patterns = @(
    '*OneDrive*'
    '*Copilot*'
    '*Teams*'
    '*Todo*'
    '*Outlook*'
    '*YourPhone*'
    '*Solitaire*'
    '*BingWeather*'
    '*BingNews*'
    '*WhatsApp*'
    '*OfficeHub*'
    'Microsoft.Office*'
    '*LinkedIn*'
    '*Adobe*Express*'
    '*windowscommunicationsapps*'
    '*MicrosoftFamily*'
    '*Clipchamp*'
    '*WebExperience*'
)

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

function Remove-ProvisionedPackage {
    param([string]$PackageName, [int]$TimeoutSec, [int]$MaxAttempts)
    return Invoke-DismItem -DismArgs @('/Online', '/Remove-ProvisionedAppxPackage', "/PackageName:$PackageName") -Label $PackageName -TimeoutSec $TimeoutSec -MaxAttempts $MaxAttempts
}

# The pre-first-logon phase should be quick; use shorter retries there so the
# Setup specialize pass is never held up for long.
$timeout  = if ($PatternsOnly) { 120 } else { 180 }
$attempts = if ($PatternsOnly) { 2 } else { 3 }

$removed = 0
$skipped = 0

if (-not $PatternsOnly) {
    foreach ($pkg in $packages) {
        Write-Host "Removing provisioned package: $pkg" -ForegroundColor Cyan
        if (Remove-ProvisionedPackage -PackageName $pkg -TimeoutSec $timeout -MaxAttempts $attempts) {
            $removed++
        }
        else {
            $skipped++
        }
    }
}

# --- Wildcard removal: provisioned packages ---
Write-Host ''
Write-Host ("Removing provisioned packages matching: {0}" -f ($patterns -join ', ')) -ForegroundColor Cyan
try {
    $provisioned = @(Get-AppxProvisionedPackage -Online -ErrorAction Stop)
}
catch {
    $provisioned = @()
    Write-Host ('  could not enumerate provisioned packages: ' + $_.Exception.Message) -ForegroundColor Red
}

foreach ($item in $provisioned) {
    $display = [string]$item.DisplayName
    $name    = if ($item.PackageName) { [string]$item.PackageName } else { $display }
    $match = $false
    foreach ($pattern in $patterns) {
        if ($display -like $pattern -or $name -like $pattern) { $match = $true; break }
    }
    if (-not $match) { continue }

    Write-Host "Removing provisioned package: $name" -ForegroundColor Cyan
    if (Remove-ProvisionedPackage -PackageName $name -TimeoutSec $timeout -MaxAttempts $attempts) {
        $removed++
    }
    else {
        $skipped++
    }
}

# --- Installed packages (all users): exact list plus patterns ---
# DISM only removes the provisioned copy of a package. Apps that are already
# installed for an existing user (for example News or Teams when the debloat
# runs at first logon) must also be removed with Remove-AppxPackage.
function Test-PackageNameMatch {
    param([string]$Name, [string]$FamilyName)
    foreach ($pkg in $packages) {
        if ($Name -eq $pkg) { return $true }
    }
    foreach ($pattern in $patterns) {
        if ($Name -like $pattern) { return $true }
        if ($FamilyName -and $FamilyName -like $pattern) { return $true }
    }
    return $false
}

Write-Host ''
Write-Host 'Removing installed packages (all users) ...' -ForegroundColor Cyan
try {
    $installed = @(Get-AppxPackage -AllUsers -ErrorAction Stop)
}
catch {
    $installed = @()
    Write-Host ('  could not enumerate installed packages: ' + $_.Exception.Message) -ForegroundColor Red
}

$seen = @{}
foreach ($app in $installed) {
    $appName  = [string]$app.Name
    $family   = [string]$app.PackageFamilyName
    $fullName = [string]$app.PackageFullName
    if (-not $fullName) { continue }
    if (-not (Test-PackageNameMatch -Name $appName -FamilyName $family)) { continue }
    if ($seen.ContainsKey($fullName)) { continue }
    $seen[$fullName] = $true
    try {
        Remove-AppxPackage -Package $fullName -AllUsers -ErrorAction Stop
        Write-Host ("  removed: {0}" -f $fullName) -ForegroundColor Green
        $removed++
    }
    catch {
        Write-Host ("  skipped ({0}): {1}" -f $_.Exception.Message, $fullName) -ForegroundColor DarkGray
        $skipped++
    }
}

Write-Host ''
Write-Host ("RemovePackages done: {0} removed, {1} skipped after retries" -f $removed, $skipped) -ForegroundColor White

if (-not $PatternsOnly) {
    Write-Host 'Applying Start menu pins ...' -ForegroundColor Cyan
    & 'C:\Windows\Setup\Scripts\SetStartPins.ps1'
}

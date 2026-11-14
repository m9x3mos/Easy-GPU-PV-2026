# EasyGPU debloat verification.
# Run inside the VM (elevated PowerShell recommended) to confirm that the
# debloat actually applied. This script only reports; it changes nothing.
$ErrorActionPreference = 'Continue'

$logFile = 'C:\Windows\Setup\Scripts\Test-Debloat.log'
$state = @{ Failures = 0 }
$results = New-Object System.Collections.Generic.List[string]

function Add-Result {
    param([string]$Status, [string]$Name, [string]$Detail = '')
    $line = if ($Detail) { '{0}  {1} ({2})' -f $Status, $Name, $Detail } else { '{0}  {1}' -f $Status, $Name }
    $results.Add($line)
    Write-Output $line
    if ($Status -eq 'FAIL') { $state.Failures++ }
}

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
$isElevated = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

Add-Result 'INFO' 'Current user' $identity.Name
Add-Result 'INFO' 'Elevated' ([string]$isElevated)
Add-Result 'INFO' 'Computer' $env:COMPUTERNAME

# --- Per-user taskbar settings ---
$advancedPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
$advanced = Get-ItemProperty -LiteralPath $advancedPath -ErrorAction SilentlyContinue

if ($advanced -and $advanced.TaskbarAl -eq 0) {
    Add-Result 'PASS' 'Taskbar is left-aligned (TaskbarAl=0)'
}
else {
    $actual = if ($advanced) { $advanced.TaskbarAl } else { 'missing' }
    Add-Result 'FAIL' 'Taskbar is left-aligned (TaskbarAl=0)' ("actual: " + $actual)
}

if ($advanced -and $advanced.ShowCopilotButton -eq 0) {
    Add-Result 'PASS' 'Copilot taskbar button disabled (ShowCopilotButton=0)'
}
else {
    $actual = if ($advanced) { $advanced.ShowCopilotButton } else { 'missing' }
    Add-Result 'FAIL' 'Copilot taskbar button disabled (ShowCopilotButton=0)' ("actual: " + $actual)
}

if ($advanced -and $advanced.ShowTaskViewButton -eq 0) {
    Add-Result 'PASS' 'Task View button disabled (ShowTaskViewButton=0)'
}
else {
    $actual = if ($advanced) { $advanced.ShowTaskViewButton } else { 'missing' }
    Add-Result 'WARN' 'Task View button disabled (ShowTaskViewButton=0)' ("actual: " + $actual)
}

# --- Taskbar pins (should be none) ---
$pinnedDir = Join-Path $env:APPDATA 'Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar'
$pinnedLinks = @()
if (Test-Path -LiteralPath $pinnedDir) {
    $pinnedLinks = @(Get-ChildItem -LiteralPath $pinnedDir -Filter '*.lnk' -ErrorAction SilentlyContinue)
}
if ($pinnedLinks.Count -eq 0) {
    Add-Result 'PASS' 'Taskbar has no pinned apps'
}
else {
    Add-Result 'FAIL' 'Taskbar has no pinned apps' (($pinnedLinks | ForEach-Object { $_.Name }) -join ', ')
}

$taskband = Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Taskband' -ErrorAction SilentlyContinue
$taskbandFavorites = if ($taskband) { @($taskband.PSObject.Properties.Name) -contains 'Favorites' } else { $false }
if (-not $taskbandFavorites) {
    Add-Result 'PASS' 'Taskbar pin store is empty (no Taskband\Favorites)'
}
else {
    Add-Result 'FAIL' 'Taskbar pin store is empty (no Taskband\Favorites)'
}

# --- Start pins (Edge, File Explorer, Store only) ---
# The Start host reads the CSP/PolicyManager value. This is the effective one.
$cspStartKey = 'HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\Start'
$cspStartPins = (Get-ItemProperty -LiteralPath $cspStartKey -Name 'ConfigureStartPins' -ErrorAction SilentlyContinue).ConfigureStartPins
if ($cspStartPins) {
    Add-Result 'PASS' 'Start pins policy is set (PolicyManager ConfigureStartPins)'
}
else {
    Add-Result 'FAIL' 'Start pins policy is set (PolicyManager ConfigureStartPins)'
}

# The Group Policy / ADMX form points at the JSON file. It is the documented
# 24H2+ GPO, but a direct registry write is only bridged on MDM-enrolled
# devices, so it is reported for information rather than as a pass/fail.
$gpoStartKey = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer'
$gpoStart = Get-ItemProperty -LiteralPath $gpoStartKey -ErrorAction SilentlyContinue
$gpoEnabled = if ($gpoStart) { $gpoStart.ConfigureStartPins } else { $null }
$gpoJsonPath = if ($gpoStart) { $gpoStart.ConfigureStartPinsJSON } else { $null }
if ($gpoEnabled -eq 1 -and $gpoJsonPath -and (Test-Path -LiteralPath $gpoJsonPath)) {
    Add-Result 'INFO' 'Start pins GPO layout file present' $gpoJsonPath
}
else {
    Add-Result 'WARN' 'Start pins GPO layout file present' ("enabled=" + $gpoEnabled + "; path=" + $gpoJsonPath)
}

# Validate the pinned list contents from whichever source is available.
$startPinsJson = $null
if ($cspStartPins) {
    $startPinsJson = $cspStartPins
}
elseif ($gpoJsonPath -and (Test-Path -LiteralPath $gpoJsonPath)) {
    $startPinsJson = Get-Content -LiteralPath $gpoJsonPath -Raw -ErrorAction SilentlyContinue
}

if ($startPinsJson) {
    try {
        $null = $startPinsJson | ConvertFrom-Json -ErrorAction Stop
        Add-Result 'PASS' 'Start pins JSON parses'
    }
    catch {
        Add-Result 'FAIL' 'Start pins JSON parses' $_.Exception.Message
    }
    if ($startPinsJson -match 'Microsoft\.WindowsStore_') {
        Add-Result 'PASS' 'Start pins include the Microsoft Store'
    }
    else {
        Add-Result 'FAIL' 'Start pins include the Microsoft Store'
    }
    if ($startPinsJson -match 'File Explorer\.lnk' -and $startPinsJson -match 'Microsoft Edge\.lnk') {
        Add-Result 'PASS' 'Start pins include Edge and File Explorer'
    }
    else {
        Add-Result 'FAIL' 'Start pins include Edge and File Explorer'
    }
    if ($startPinsJson -match 'immersivecontrolpanel') {
        Add-Result 'FAIL' 'Start pins do not include Settings'
    }
    else {
        Add-Result 'PASS' 'Start pins do not include Settings'
    }
}

# --- OneDrive leftovers ---
$runKey = Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -ErrorAction SilentlyContinue
$runNames = if ($runKey) { @($runKey.PSObject.Properties.Name) } else { @() }
if ($runNames -contains 'OneDrive' -or $runNames -contains 'OneDriveSetup') {
    Add-Result 'FAIL' 'OneDrive Run entry removed' ('found: ' + (($runNames | Where-Object { $_ -like 'OneDrive*' }) -join ', '))
}
else {
    Add-Result 'PASS' 'OneDrive Run entry removed'
}

$oneDriveClient = Join-Path $env:LOCALAPPDATA 'Microsoft\OneDrive'
if (Test-Path -LiteralPath $oneDriveClient) {
    Add-Result 'FAIL' 'OneDrive client folder removed' $oneDriveClient
}
else {
    Add-Result 'PASS' 'OneDrive client folder removed'
}

$setupPaths = @(
    'C:\Windows\System32\OneDriveSetup.exe'
    'C:\Windows\SysWOW64\OneDriveSetup.exe'
)
$setupFound = @($setupPaths | Where-Object { Test-Path -LiteralPath $_ })
if ($setupFound.Count -gt 0) {
    Add-Result 'FAIL' 'OneDrive setup binaries removed' ($setupFound -join ', ')
}
else {
    Add-Result 'PASS' 'OneDrive setup binaries removed'
}

# --- Installed and provisioned packages ---
$patterns = @(
    '*Copilot*'
    '*OneDrive*'
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

# --- Xbox app is intentionally kept ---
if (@($patterns | Where-Object { 'Microsoft.GamingApp' -like $_ }).Count -eq 0) {
    Add-Result 'PASS' 'Xbox app is allowed (not in the removal list)'
}
else {
    Add-Result 'FAIL' 'Xbox app is allowed (not in the removal list)'
}

foreach ($pattern in $patterns) {
    try {
        $apps = @(Get-AppxPackage -AllUsers -Name $pattern -ErrorAction Stop)
        if ($apps.Count -eq 0) {
            Add-Result 'PASS' ("No installed packages matching {0}" -f $pattern)
        }
        else {
            Add-Result 'FAIL' ("Installed packages matching {0}" -f $pattern) (($apps | ForEach-Object { $_.PackageFullName }) -join ', ')
        }
    }
    catch {
        Add-Result 'WARN' ("Could not enumerate installed packages matching {0}" -f $pattern) $_.Exception.Message
    }
}

try {
    $provisioned = @(Get-AppxProvisionedPackage -Online -ErrorAction Stop)
    foreach ($pattern in $patterns) {
        $provisionedMatches = @($provisioned | Where-Object {
            ([string]$_.DisplayName -like $pattern) -or ([string]$_.PackageName -like $pattern)
        })
        if ($provisionedMatches.Count -eq 0) {
            Add-Result 'PASS' ("No provisioned packages matching {0}" -f $pattern)
        }
        else {
            Add-Result 'FAIL' ("Provisioned packages matching {0}" -f $pattern) (($provisionedMatches | ForEach-Object {
                if ($_.PackageName) { [string]$_.PackageName } else { [string]$_.DisplayName }
            }) -join ', ')
        }
    }
}
catch {
    Add-Result 'WARN' 'Could not enumerate provisioned packages' $_.Exception.Message
}

# --- Machine policies ---
$policyChecks = @(
    @{ Path = 'HKLM:\Software\Policies\Microsoft\Windows\OneDrive'; Name = 'DisableFileSyncNGSC' }
    @{ Path = 'HKLM:\Software\Policies\Microsoft\Windows\OneDrive'; Name = 'DisableFileSync' }
    @{ Path = 'HKLM:\Software\Policies\Microsoft\Windows\WindowsCopilot'; Name = 'TurnOffWindowsCopilot' }
)
foreach ($check in $policyChecks) {
    $property = Get-ItemProperty -LiteralPath $check.Path -Name $check.Name -ErrorAction SilentlyContinue
    $value = if ($property) { $property.PSObject.Properties[$check.Name].Value } else { $null }
    if ($value -eq 1) {
        Add-Result 'PASS' ("Policy {0}\{1}=1" -f $check.Path, $check.Name)
    }
    else {
        Add-Result 'FAIL' ("Policy {0}\{1}=1" -f $check.Path, $check.Name) ("actual: " + $value)
    }
}

# --- Widgets and Start "All apps" view ---
# Widgets are removed by uninstalling the Windows Web Experience Pack
# (matched by the *WebExperience* pattern above) and by hiding the taskbar
# button. AllowNewsAndInterests=0 is the supporting machine policy.
$dshKey = 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh'
$dsh = Get-ItemProperty -LiteralPath $dshKey -ErrorAction SilentlyContinue
if ($dsh -and $dsh.AllowNewsAndInterests -eq 0) {
    Add-Result 'PASS' 'Widgets/News and interests disabled (AllowNewsAndInterests=0)'
}
else {
    $actual = if ($dsh) { $dsh.AllowNewsAndInterests } else { 'missing' }
    Add-Result 'WARN' 'Widgets/News and interests disabled (AllowNewsAndInterests=0)' ("actual: " + $actual)
}
$webExperience = @(Get-AppxPackage -AllUsers -Name '*WebExperience*' -ErrorAction SilentlyContinue)
if ($webExperience.Count -eq 0) {
    Add-Result 'PASS' 'Widgets removed (no Windows Web Experience Pack installed)'
}
else {
    Add-Result 'FAIL' 'Widgets removed (no Windows Web Experience Pack installed)' (($webExperience | ForEach-Object { $_.PackageFullName }) -join ', ')
}

$startViewKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Start'
$allAppsViewMode = (Get-ItemProperty -LiteralPath $startViewKey -Name 'AllAppsViewMode' -ErrorAction SilentlyContinue).AllAppsViewMode
if ($allAppsViewMode -eq 2) {
    Add-Result 'PASS' 'Start All apps view is List (AllAppsViewMode=2)'
}
else {
    Add-Result 'FAIL' 'Start All apps view is List (AllAppsViewMode=2)' ("actual: " + $allAppsViewMode)
}

$taskbarDa = (Get-ItemProperty -LiteralPath $advancedPath -Name 'TaskbarDa' -ErrorAction SilentlyContinue).TaskbarDa
if ($taskbarDa -eq 0) {
    Add-Result 'PASS' 'Widgets taskbar button hidden (TaskbarDa=0)'
}
else {
    Add-Result 'WARN' 'Widgets taskbar button hidden (TaskbarDa=0)' ("actual: " + $taskbarDa)
}

# --- Logs and flags ---
$artifacts = @(
    'C:\Windows\Setup\Scripts\PreFirstLogon.log'
    'C:\Windows\Setup\Scripts\debloat.log'
    'C:\ProgramData\Easy-GPU-P\pre-first-logon.flag'
    'C:\ProgramData\Easy-GPU-P\debloat-complete.flag'
)
foreach ($artifact in $artifacts) {
    if (Test-Path -LiteralPath $artifact) {
        Add-Result 'INFO' ("Present: {0}" -f $artifact)
    }
    else {
        Add-Result 'WARN' ("Missing: {0}" -f $artifact)
    }
}

$status = if ($state.Failures -eq 0) { 'PASS' } else { 'FAIL' }
$summary = 'RESULT: {0} ({1} failure(s))' -f $status, $state.Failures
Add-Result 'INFO' $summary

try {
    Add-Content -LiteralPath $logFile -Value ('--- {0} ---' -f (Get-Date -Format 'o')) -Encoding UTF8
    foreach ($line in $results) { Add-Content -LiteralPath $logFile -Value $line -Encoding UTF8 }
}
catch { }

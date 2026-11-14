# EasyGPU pre-first-logon debloat.
# Runs during the Windows Setup "specialize" pass (see autounattend.xml),
# before the GPUVM user profile is created. This keeps OneDrive, Copilot, and
# the bundled apps that are removed below from installing into the new profile.
$ErrorActionPreference = 'Continue'

$scriptDir = 'C:\Windows\Setup\Scripts'
$pkgDir    = 'C:\ProgramData\Easy-GPU-P'
$logFile   = Join-Path $scriptDir 'PreFirstLogon.log'
$flagPath  = Join-Path $pkgDir 'pre-first-logon.flag'

function Write-PreLog {
    param([string]$Message, [string]$Level = 'INFO')
    $line = ('{0}  [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message)
    Write-Output $line
    try {
        $logDir = Split-Path -Parent $logFile
        if ($logDir -and -not (Test-Path -LiteralPath $logDir)) { New-Item -Path $logDir -ItemType Directory -Force | Out-Null }
        Add-Content -LiteralPath $logFile -Value $line -Encoding UTF8
    }
    catch { }
}

if (Test-Path -LiteralPath $flagPath) {
    Write-PreLog 'Pre-first-logon already completed (flag present). Skipping.'
    return
}

Write-PreLog '=== EasyGPU pre-first-logon starting ==='

# 1) Remove the OneDrive setup binaries and shortcuts from disk before the new
#    profile is created.
$oneDriveFiles = @(
    'C:\Windows\System32\OneDriveSetup.exe'
    'C:\Windows\SysWOW64\OneDriveSetup.exe'
    'C:\Users\Default\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\OneDrive.lnk'
    'C:\ProgramData\Microsoft\Windows\Start Menu\Programs\OneDrive.lnk'
)
foreach ($path in $oneDriveFiles) {
    if (Test-Path -LiteralPath $path) {
        try {
            Remove-Item -LiteralPath $path -Force -ErrorAction Stop
            Write-PreLog ("Removed {0}" -f $path)
        }
        catch {
            Write-PreLog ("WARNING: could not remove {0}: {1}" -f $path, $_.Exception.Message) 'WARN'
        }
    }
    else {
        Write-PreLog ("Already absent: {0}" -f $path)
    }
}

# 2) Remove the provisioned OneDrive, Copilot, and bundled app packages.
$removePackages = Join-Path $scriptDir 'RemovePackages.ps1'
if (Test-Path -LiteralPath $removePackages) {
    Write-PreLog 'Running RemovePackages.ps1 -PatternsOnly ...'
    try { & $removePackages -PatternsOnly }
    catch { Write-PreLog ('RemovePackages.ps1 ERROR: ' + $_.Exception.Message) 'ERROR' }
}
else {
    Write-PreLog ("WARNING: {0} not found." -f $removePackages) 'WARN'
}

# 3) Machine-wide policies that block OneDrive and Copilot.
$policyValues = @(
    @{ Path = 'HKLM\Software\Policies\Microsoft\Windows\OneDrive'; Name = 'DisableFileSyncNGSC'; Value = 1 }
    @{ Path = 'HKLM\Software\Policies\Microsoft\Windows\OneDrive'; Name = 'DisableFileSync'; Value = 1 }
    @{ Path = 'HKLM\Software\Policies\Microsoft\Windows\WindowsCopilot'; Name = 'TurnOffWindowsCopilot'; Value = 1 }
)
foreach ($policy in $policyValues) {
    & reg.exe add $policy.Path /v $policy.Name /t REG_DWORD /d $policy.Value /f *> $null
    if ($LASTEXITCODE -eq 0) {
        Write-PreLog ("Policy set: {0}\{1}={2}" -f $policy.Path, $policy.Name, $policy.Value)
    }
    else {
        Write-PreLog ("WARNING: policy {0}\{1} failed (exit {2})." -f $policy.Path, $policy.Name, $LASTEXITCODE) 'WARN'
    }
}

# 3b) Make sure the event source used by the Start-layout unlock task exists.
try {
    if (-not [System.Diagnostics.EventLog]::SourceExists('UnattendGenerator')) {
        [System.Diagnostics.EventLog]::CreateEventSource('UnattendGenerator', 'Application')
        Write-PreLog 'Created event source UnattendGenerator.'
    }
    else {
        Write-PreLog 'Event source UnattendGenerator already exists.'
    }
}
catch {
    Write-PreLog ('WARNING: could not create UnattendGenerator event source: ' + $_.Exception.Message) 'WARN'
}

# 4) Default-profile template. DefaultUser.ps1 loads C:\Users\Default\NTUSER.DAT,
#    applies the settings, removes the OneDriveSetup Run entry, and unloads it.
$defaultUser = Join-Path $scriptDir 'DefaultUser.ps1'
if (Test-Path -LiteralPath $defaultUser) {
    Write-PreLog 'Running DefaultUser.ps1 ...'
    try { & $defaultUser }
    catch { Write-PreLog ('DefaultUser.ps1 ERROR: ' + $_.Exception.Message) 'ERROR' }
}
else {
    Write-PreLog ("WARNING: {0} not found." -f $defaultUser) 'WARN'
}

# 5) Start menu pins policy.
$startPins = Join-Path $scriptDir 'SetStartPins.ps1'
if (Test-Path -LiteralPath $startPins) {
    Write-PreLog 'Running SetStartPins.ps1 ...'
    try { & $startPins }
    catch { Write-PreLog ('SetStartPins.ps1 ERROR: ' + $_.Exception.Message) 'ERROR' }
}
else {
    Write-PreLog ("WARNING: {0} not found." -f $startPins) 'WARN'
}

# 6) Verify the important results.
$failures = 0

foreach ($path in $oneDriveFiles) {
    if (Test-Path -LiteralPath $path) {
        Write-PreLog ("VERIFY FAIL: still present: {0}" -f $path) 'FAIL'
        $failures++
    }
}

$verifyPatterns = @(
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

try {
    $provisioned = @(Get-AppxProvisionedPackage -Online -ErrorAction Stop)
    foreach ($item in $provisioned) {
        $display = [string]$item.DisplayName
        $name    = [string]$item.PackageName
        $hit = $null
        foreach ($pattern in $verifyPatterns) {
            if ($display -like $pattern -or $name -like $pattern) { $hit = $pattern; break }
        }
        if ($hit) {
            $label = if ($name) { $name } else { $display }
            Write-PreLog ("VERIFY FAIL: provisioned package still present: {0}" -f $label) 'FAIL'
            $failures++
        }
    }
}
catch {
    Write-PreLog ('VERIFY WARN: could not enumerate provisioned packages: ' + $_.Exception.Message) 'WARN'
}

$policyChecks = @(
    @{ Path = 'HKLM:\Software\Policies\Microsoft\Windows\OneDrive'; Name = 'DisableFileSyncNGSC' }
    @{ Path = 'HKLM:\Software\Policies\Microsoft\Windows\OneDrive'; Name = 'DisableFileSync' }
    @{ Path = 'HKLM:\Software\Policies\Microsoft\Windows\WindowsCopilot'; Name = 'TurnOffWindowsCopilot' }
)
foreach ($check in $policyChecks) {
    $property = Get-ItemProperty -LiteralPath $check.Path -Name $check.Name -ErrorAction SilentlyContinue
    $value = if ($property) { $property.PSObject.Properties[$check.Name].Value } else { $null }
    if ($value -ne 1) {
        Write-PreLog ("VERIFY FAIL: policy not set: {0}\{1}" -f $check.Path, $check.Name) 'FAIL'
        $failures++
    }
}

if ($failures -eq 0) {
    Write-PreLog 'Verification PASSED.'
}
else {
    Write-PreLog ("Verification finished with {0} failure(s); the first-logon debloat will still run." -f $failures) 'WARN'
}

# 7) Completion flag. Always write it so the first-logon chain can log that this
#    phase ran; the first-logon debloat still runs as a safety net.
try {
    if (-not (Test-Path -LiteralPath $pkgDir)) { New-Item -Path $pkgDir -ItemType Directory -Force | Out-Null }
    Set-Content -LiteralPath $flagPath -Value ((Get-Date).ToString('o')) -Encoding UTF8
    Write-PreLog ("Wrote completion flag: {0}" -f $flagPath)
}
catch {
    Write-PreLog ('WARNING: could not write completion flag: ' + $_.Exception.Message) 'WARN'
}

Write-PreLog '=== EasyGPU pre-first-logon finished ==='

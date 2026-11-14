# EasyGPU default-profile configuration.
#
# C:\Users\Default\NTUSER.DAT is the template Windows copies when it creates a
# new profile. It is NOT mounted at HKU\Default, so load it explicitly, apply
# the settings, then unload it again.
$ErrorActionPreference = 'Continue'

$hiveName = 'EasyGPUDefault'
$hiveKey  = 'HKU\' + $hiveName
$hiveFile = 'C:\Users\Default\NTUSER.DAT'
$logFile  = 'C:\Windows\Setup\Scripts\DefaultUser.log'

function Write-DefaultUserLog {
	param([string]$Message)
	$line = ('{0}  {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message)
	try {
		$logDir = Split-Path -Parent $logFile
		if ($logDir -and -not (Test-Path -LiteralPath $logDir)) { New-Item -Path $logDir -ItemType Directory -Force | Out-Null }
		Add-Content -LiteralPath $logFile -Value $line -Encoding UTF8
	}
	catch { }
	Write-Output $line
}

# Remove a leftover hive from an earlier failed run, otherwise reg load fails.
$shouldUnload = $false
$hiveAvailable = $false
if (Test-Path -LiteralPath ('Registry::' + $hiveKey)) {
	$shouldUnload = $true
	Write-DefaultUserLog ("Hive {0} is already loaded; unloading it first." -f $hiveKey)
	[gc]::Collect()
	[gc]::WaitForPendingFinalizers()
	& reg.exe unload $hiveKey *> $null
	if ($LASTEXITCODE -eq 0) {
		Write-DefaultUserLog ("Unloaded stale hive {0}." -f $hiveKey)
	}
	else {
		Write-DefaultUserLog ("WARNING: could not unload stale hive {0} (exit {1}); continuing." -f $hiveKey, $LASTEXITCODE)
	}
}

try {
	& reg.exe load $hiveKey $hiveFile *> $null
	if ($LASTEXITCODE -eq 0) {
		$hiveAvailable = $true
		$shouldUnload = $true
		Write-DefaultUserLog ("Loaded default profile hive {0} from {1}." -f $hiveKey, $hiveFile)
	}
	else {
		Write-DefaultUserLog ("WARNING: reg load {0} failed with exit code {1}." -f $hiveKey, $LASTEXITCODE)
	}
}
catch {
	Write-DefaultUserLog ('WARNING: could not load default profile hive: ' + $_.Exception.Message)
}

# Fall back to a hive that is already loaded (for example from a previous run).
if (-not $hiveAvailable -and (Test-Path -LiteralPath ('Registry::' + $hiveKey))) {
	$hiveAvailable = $true
	$shouldUnload = $true
}

if (-not $hiveAvailable) {
	Write-DefaultUserLog ("ERROR: {0} is not available; skipping default-profile settings." -f $hiveKey)
	return
}

try {
	$scripts = @(
		{
			& reg.exe add "$hiveKey\Software\Policies\Microsoft\Windows\WindowsCopilot" /v TurnOffWindowsCopilot /t REG_DWORD /d 1 /f;
		};
		{
			& reg.exe add "$hiveKey\Software\Microsoft\Internet Explorer\LowRegistry\Audio\PolicyConfig\PropertyStore" /f;
		};
		{
			# Use reg.exe instead of the registry provider so no hive handle is
			# left open when the hive is unloaded below.
			& reg.exe delete "$hiveKey\Software\Microsoft\Windows\CurrentVersion\Run" /v "OneDriveSetup" /f 2>&1 | Out-Null;
		};
		{
			& reg.exe add "$hiveKey\Software\Policies\Microsoft\Windows\Explorer" /v "StartLayoutFile" /t REG_SZ /d "C:\Windows\Setup\Scripts\TaskbarLayoutModification.xml" /f;
			& reg.exe add "$hiveKey\Software\Policies\Microsoft\Windows\Explorer" /v "LockedStartLayout" /t REG_DWORD /d 1 /f;
		};
		{
			& reg.exe add "$hiveKey\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v "HideFileExt" /t REG_DWORD /d 0 /f;
		};
		{
			& reg.exe add "$hiveKey\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v "Hidden" /t REG_DWORD /d 1 /f;
		};
		{
			& reg.exe add "$hiveKey\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v ShowTaskViewButton /t REG_DWORD /d 0 /f;
		};
		{
			& reg.exe add "$hiveKey\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v TaskbarAl /t REG_DWORD /d 0 /f;
		};
		{
			& reg.exe add "$hiveKey\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v ShowCopilotButton /t REG_DWORD /d 0 /f;
		};
		{
			& reg.exe add "$hiveKey\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v Start_IcoPosition /t REG_DWORD /d 1 /f;
		};
		{
			# Hide the Widgets taskbar button (0 = hidden).
			& reg.exe add "$hiveKey\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v TaskbarDa /t REG_DWORD /d 0 /f;
		};
		{
			# Start menu "All apps" view: list instead of the default
			# category layout (0=Category, 1=Grid, 2=List).
			& reg.exe add "$hiveKey\Software\Microsoft\Windows\CurrentVersion\Start" /v AllAppsViewMode /t REG_DWORD /d 2 /f;
		};
		{
			& reg.exe add "$hiveKey\Software\Policies\Microsoft\Windows\Explorer" /v DisableSearchBoxSuggestions /t REG_DWORD /d 1 /f;
		};
		{
			& reg.exe add "$hiveKey\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\TaskbarDeveloperSettings" /v TaskbarEndTask /t REG_DWORD /d 1 /f;
		};
		{
			& reg.exe add "$hiveKey\Software\Microsoft\Windows\DWM" /v ColorPrevalence /t REG_DWORD /d 0 /f;
		};
		{
			& reg.exe add "$hiveKey\Software\Microsoft\Windows\CurrentVersion\RunOnce" /v "UnattendedSetup" /t REG_SZ /d "powershell.exe -WindowStyle \""Normal\"" -ExecutionPolicy \""Unrestricted\"" -NoProfile -File \""C:\Windows\Setup\Scripts\UserOnce.ps1\""" /f;
		};
	);

	& {
		foreach( $script in $scripts ) {
			'*** Will now execute command «{0}».' -f $(
				$script.ToString().Trim() -replace '\s+', ' ' -replace '^(.{99})(.+)$', '$1…';
			);
			$start = [datetime]::Now;
			& $script;
			'*** Finished executing command after {0:0} ms.' -f [datetime]::Now.Subtract( $start ).TotalMilliseconds;
			"`r`n" * 3;
		}
	} *>&1 | Tee-Object -Append -FilePath $logFile;
}
finally {
	if ($shouldUnload) {
		# Release any handles the registry provider may still hold, then unload.
		# Retry a few times: an unload must succeed for the hive changes to be
		# flushed to C:\Users\Default\NTUSER.DAT.
		$unloaded = $false
		for ($attempt = 1; $attempt -le 5; $attempt++) {
			[gc]::Collect()
			[gc]::WaitForPendingFinalizers()
			Start-Sleep -Milliseconds 500
			& reg.exe unload $hiveKey *> $null
			if ($LASTEXITCODE -eq 0) {
				$unloaded = $true
				break
			}
			Write-DefaultUserLog ("WARNING: reg unload {0} attempt {1} failed with exit code {2}." -f $hiveKey, $attempt, $LASTEXITCODE)
		}
		if ($unloaded) {
			Write-DefaultUserLog ("Unloaded default profile hive {0}." -f $hiveKey)
		}
		else {
			Write-DefaultUserLog ("ERROR: could not unload default profile hive {0}; settings may not persist." -f $hiveKey)
		}
	}
}

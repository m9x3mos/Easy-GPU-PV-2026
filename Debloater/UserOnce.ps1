# EasyGPU per-user debloat.
# This runs in the logged-on user's session (interactive scheduled task or
# RunOnce), so HKCU and the Explorer restart apply to the real desktop.
$ErrorActionPreference = 'Continue'

$logFile = 'C:\Windows\Setup\Scripts\UserOnce.log'
try { Add-Content -LiteralPath $logFile -Value ('--- {0} ---' -f (Get-Date -Format 'o')) -ErrorAction Stop }
catch { $logFile = Join-Path $env:TEMP 'UserOnce.log' }

# Bundled apps to remove from the current user. The full RemovePackages.ps1 run
# removes these for all users; this is a second safety net in the user session.
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

$scripts = @(
	{
		# Remove the bundled apps for the current user.
		foreach ($pattern in $patterns) {
			Get-AppxPackage -Name $pattern -ErrorAction 'SilentlyContinue' | Remove-AppxPackage -ErrorAction 'SilentlyContinue';
		}
	};
	{
		# Stop and uninstall the per-user OneDrive client if it was installed
		# before this script ran.
		Get-Process -Name 'OneDrive', 'Microsoft.OneDriveSync' -ErrorAction 'SilentlyContinue' | Stop-Process -Force -ErrorAction 'SilentlyContinue';
		$setup = @(
			'C:\Windows\System32\OneDriveSetup.exe'
			'C:\Windows\SysWOW64\OneDriveSetup.exe'
			(Join-Path $env:LOCALAPPDATA 'Microsoft\OneDrive\OneDriveSetup.exe')
		) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1;
		if ($setup) {
			& $setup /uninstall | Out-Null;
		}
		Remove-ItemProperty -LiteralPath 'Registry::HKCU\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'OneDrive', 'OneDriveSetup' -Force -ErrorAction 'SilentlyContinue';
		Remove-Item -LiteralPath @(
			(Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\OneDrive.lnk')
			(Join-Path $env:LOCALAPPDATA 'Microsoft\OneDrive')
		) -Recurse -Force -ErrorAction 'SilentlyContinue';
	};
	{
		# Notify the event-driven UnlockStartLayout task. Never let event-log
		# permissions stop the rest of the per-user debloat.
		try {
			$source = 'UnattendGenerator';
			if (-not [System.Diagnostics.EventLog]::SourceExists($source)) {
				[System.Diagnostics.EventLog]::CreateEventSource($source, 'Application');
			}
			[System.Diagnostics.EventLog]::WriteEntry( $source, "User '$env:USERNAME' has requested to unlock the Start menu layout.", [System.Diagnostics.EventLogEntryType]::Information, 1 );
		}
		catch {
			Write-Warning ('Could not write UnlockStartLayout event: ' + $_.Exception.Message);
		}
	};
	{
		# Taskbar: left-aligned, no Copilot button, no Task View button,
		# no Widgets button.
		$advanced = 'Registry::HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced';
		Set-ItemProperty -LiteralPath $advanced -Name 'TaskbarAl' -Value 0 -Type 'DWord' -Force;
		Set-ItemProperty -LiteralPath $advanced -Name 'ShowCopilotButton' -Value 0 -Type 'DWord' -Force;
		Set-ItemProperty -LiteralPath $advanced -Name 'ShowTaskViewButton' -Value 0 -Type 'DWord' -Force;
		Set-ItemProperty -LiteralPath $advanced -Name 'TaskbarDa' -Value 0 -Type 'DWord' -Force;
		Set-ItemProperty -LiteralPath $advanced -Name 'HideFileExt' -Value 0 -Type 'DWord' -Force;
		Set-ItemProperty -LiteralPath $advanced -Name 'Hidden' -Value 1 -Type 'DWord' -Force;
		Set-ItemProperty -LiteralPath $advanced -Name 'Start_IcoPosition' -Value 1 -Type 'DWord' -Force;
	};
	{
		# Taskbar: pin nothing. Windows seeds the default pins (Edge, File
		# Explorer, Store, Outlook) when the profile is created, and the
		# "remove all pins" layout alone does not clear them from an existing
		# profile, so clear the pin store and re-apply the empty layout.
		$pinned = Join-Path $env:APPDATA 'Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar';
		if (Test-Path -LiteralPath $pinned) {
			Get-ChildItem -LiteralPath $pinned -Filter '*.lnk' -ErrorAction 'SilentlyContinue' | Remove-Item -Force -ErrorAction 'SilentlyContinue';
		}
		Remove-Item -LiteralPath 'Registry::HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Taskband' -Recurse -Force -ErrorAction 'SilentlyContinue';
		$explorerPolicy = 'Registry::HKCU\Software\Policies\Microsoft\Windows\Explorer';
		if (-not (Test-Path -LiteralPath $explorerPolicy)) { New-Item -Path $explorerPolicy -Force | Out-Null; }
		Set-ItemProperty -LiteralPath $explorerPolicy -Name 'StartLayoutFile' -Value 'C:\Windows\Setup\Scripts\TaskbarLayoutModification.xml' -Type 'String' -Force;
		Set-ItemProperty -LiteralPath $explorerPolicy -Name 'LockedStartLayout' -Value 1 -Type 'DWord' -Force;
	};
	{
		$dev = 'Registry::HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\TaskbarDeveloperSettings';
		if (-not (Test-Path -LiteralPath $dev)) { New-Item -Path $dev -Force | Out-Null; }
		Set-ItemProperty -LiteralPath $dev -Name 'TaskbarEndTask' -Value 1 -Type 'DWord' -Force;
	};
	{
		Set-ItemProperty -LiteralPath 'Registry::HKCU\Software\Microsoft\Windows\CurrentVersion\Search' -Name 'SearchboxTaskbarMode' -Type 'DWord' -Value 0 -Force;
	};
	{
		& 'C:\Windows\Setup\Scripts\SetColorTheme.ps1';
	};
	{
		# Start menu "All apps" view: list instead of the default category
		# layout (0=Category, 1=Grid, 2=List).
		$startKey = 'Registry::HKCU\Software\Microsoft\Windows\CurrentVersion\Start';
		if (-not (Test-Path -LiteralPath $startKey)) { New-Item -Path $startKey -Force | Out-Null; }
		Set-ItemProperty -LiteralPath $startKey -Name 'AllAppsViewMode' -Value 2 -Type 'DWord' -Force;
	};
	{
		# Start menu: the pinned list comes from the ConfigureStartPins machine
		# policy, but Windows caches the built Start layout per profile. A
		# profile that already exists keeps its old (default) pins until that
		# cache is cleared, so drop it and let Start rebuild from the policy.
		Get-Process -Name 'StartMenuExperienceHost' -ErrorAction 'SilentlyContinue' | Stop-Process -Force -ErrorAction 'SilentlyContinue';
		$startState = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.Windows.StartMenuExperienceHost_cw5n1h2txyewy\LocalState';
		foreach ($file in 'start2.bin', 'start.bin') {
			$path = Join-Path $startState $file;
			if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force -ErrorAction 'SilentlyContinue'; }
		}
		$cloudStore = 'Registry::HKCU\Software\Microsoft\Windows\CurrentVersion\CloudStore\Store\Cache\DefaultAccount';
		if (Test-Path -LiteralPath $cloudStore) {
			Get-ChildItem -LiteralPath $cloudStore -ErrorAction 'SilentlyContinue' |
				Where-Object { $_.PSChildName -like '*start.tilegrid*' -or $_.PSChildName -like '*curatedtilecollection*' } |
				Remove-Item -Recurse -Force -ErrorAction 'SilentlyContinue';
		}
	};
	{
		Get-Process -Name 'explorer' -ErrorAction 'SilentlyContinue' | Where-Object -FilterScript {
			$_.SessionId -eq ( Get-Process -Id $PID ).SessionId;
		} | Stop-Process -Force;
	};
	{
		# Let Explorer start and apply the empty taskbar layout, then unlock it so
		# the user can pin apps later if they want. Nothing is pinned by default.
		Start-Sleep -Seconds 5;
		$explorerPolicy = 'Registry::HKCU\Software\Policies\Microsoft\Windows\Explorer';
		if (Test-Path -LiteralPath $explorerPolicy) {
			Set-ItemProperty -LiteralPath $explorerPolicy -Name 'LockedStartLayout' -Value 0 -Type 'DWord' -Force;
		}
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

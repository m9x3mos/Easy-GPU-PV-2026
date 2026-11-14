$ErrorActionPreference = 'Continue';

# Windows 11 Start menu pins (Edge, File Explorer, Store only).
#
# The Start host reads the "Configure Start Pins" policy from the CSP /
# PolicyManager store:
#   HKLM\SOFTWARE\Microsoft\PolicyManager\current\device\Start
#     ConfigureStartPins          = <single-line JSON content>  (REG_SZ)
#     ConfigureStartPins_ProviderSet = 1                        (DWORD)
# This is the only form that applies on a machine that is not MDM-enrolled,
# and it is honored when the profile is created (and reapplied on sign-in).
#
# The Group Policy / ADMX form is written as well:
#   HKLM\SOFTWARE\Policies\Microsoft\Windows\Explorer
#     ConfigureStartPins     = 1                                 (DWORD)
#     ConfigureStartPinsJSON = <path to the JSON file>           (REG_EXPAND_SZ)
# That is exactly what StartMenu.admx defines, but a direct registry write is
# only bridged into the PolicyManager store on MDM-enrolled devices, so on a
# plain image it is inert. It is kept for completeness.
$json = '{"pinnedList":[{"desktopAppLink":"%ALLUSERSPROFILE%\\Microsoft\\Windows\\Start Menu\\Programs\\Microsoft Edge.lnk"},{"desktopAppLink":"%APPDATA%\\Microsoft\\Windows\\Start Menu\\Programs\\File Explorer.lnk"},{"packagedAppId":"Microsoft.WindowsStore_8wekyb3d8bbwe!App"}]}';

if( [System.Environment]::OSVersion.Version.Build -lt 20000 ) {
	return;
}

# 1) The JSON file the Group Policy form points at. Keep it ASCII so no byte
#    order mark is written (a BOM can make the Start menu reject the file).
$jsonPath = 'C:\Windows\Setup\Scripts\StartPins.json';
Set-Content -LiteralPath $jsonPath -Value $json -Encoding 'ASCII' -Force;

# 2) Group Policy / ADMX form.
$policyKey = 'Registry::HKLM\SOFTWARE\Policies\Microsoft\Windows\Explorer';
if (-not (Test-Path -LiteralPath $policyKey)) {
	New-Item -Path $policyKey -ItemType 'Directory' -Force | Out-Null;
}
Set-ItemProperty -LiteralPath $policyKey -Name 'ConfigureStartPins' -Value 1 -Type 'DWord' -Force;
Set-ItemProperty -LiteralPath $policyKey -Name 'ConfigureStartPinsJSON' -Value $jsonPath -Type 'ExpandString' -Force;

# 3) CSP / provisioning form (JSON content, with the ProviderSet marker).
$cspKey = 'Registry::HKLM\SOFTWARE\Microsoft\PolicyManager\current\device\Start';
if (-not (Test-Path -LiteralPath $cspKey)) {
	New-Item -Path $cspKey -ItemType 'Directory' -Force | Out-Null;
}
Set-ItemProperty -LiteralPath $cspKey -Name 'ConfigureStartPins' -Value $json -Type 'String' -Force;
Set-ItemProperty -LiteralPath $cspKey -Name 'ConfigureStartPins_ProviderSet' -Value 1 -Type 'DWord' -Force;

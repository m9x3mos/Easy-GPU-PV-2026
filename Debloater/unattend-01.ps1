Stop-Service -Name wsaifabricsvc -Force
Set-Service -Name wsaifabricsvc -StartupType Disabled
$path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent"

# Create the key if it doesn't exist
if (-not (Test-Path $path)) {
    New-Item -Path $path -Force | Out-Null
}

# Set the DWORD values
New-ItemProperty -Path $path -Name "DisableCloudOptimizedContent" -PropertyType DWord -Value 1 -Force | Out-Null
New-ItemProperty -Path $path -Name "DisableWindowsConsumerFeatures" -PropertyType DWord -Value 1 -Force | Out-Null

Invoke-Item "C:\Windows\Resources\Themes\dark.theme"

Start-Sleep -Seconds 60
Restart-Computer -Force
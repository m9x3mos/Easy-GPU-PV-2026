$scripts = @(
	{
		$winlogon = 'Registry::HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon';
		Set-ItemProperty -LiteralPath $winlogon -Name 'AutoAdminLogon' -Value 1 -Type 'DWord' -Force;
		Set-ItemProperty -LiteralPath $winlogon -Name 'DefaultUserName' -Value 'GPUVM' -Type 'String' -Force;
		Set-ItemProperty -LiteralPath $winlogon -Name 'DefaultPassword' -Value 'CoolestPassword!' -Type 'String' -Force;
		Remove-ItemProperty -LiteralPath $winlogon -Name 'AutoLogonCount' -Force -ErrorAction 'SilentlyContinue';
	};
	{
		cmd.exe /c "rmdir C:\Windows.old";
	};
	{
		& 'C:\Windows\Setup\Scripts\unattend-01.ps1';
	};
	{
		Remove-Item -LiteralPath @(
		  'C:\Windows\Panther\unattend.xml';
		  'C:\Windows\Panther\unattend-original.xml';
		  'C:\Windows\Setup\Scripts\Wifi.xml';
		) -Force -ErrorAction 'SilentlyContinue' -Verbose;
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
} *>&1 | Tee-Object -Append -FilePath "C:\Windows\Setup\Scripts\FirstLogon.log";
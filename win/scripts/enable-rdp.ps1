$ErrorActionPreference = 'Stop'
try {
  Start-Transcript -Path 'C:\Windows\Temp\vagrant-provision.log' -Append -ErrorAction SilentlyContinue | Out-Null

  # Enable Remote Desktop
  Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' -Name 'fDenyTSConnections' -Value 0

  # Open Windows Firewall for RDP
  try { Enable-NetFirewallRule -DisplayGroup 'Remote Desktop' -ErrorAction Stop | Out-Null } catch { }
  try { netsh advfirewall firewall set rule group='remote desktop' new enable=Yes | Out-Null } catch { }

  Write-Host 'RDP enabled and firewall rules applied.'
  Stop-Transcript | Out-Null
  exit 0
} catch {
  Write-Host ('Provisioning warning: ' + $_.Exception.Message)
  try { Stop-Transcript | Out-Null } catch { }
  exit 0
}



## Enable RDP after deployment
RDP is disabled for security reasons - PS remoting should work. Remote into a node using e.g. *etsn node1* and do a:  
```c#
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name "fDenyTSConnections" -Value 0
Enable-NetFirewallRule -DisplayGroup "Remote Desktop"
```
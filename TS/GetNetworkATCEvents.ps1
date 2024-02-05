if (!(Test-Path c:\temp)){mkdir c:\temp}
Start-Transcript c:\temp\NetworkATCEvents.log

Get-WinEvent -LogName "Microsoft-Windows-Networking-NetworkAtc/Operational" -MaxEvents 10

Get-WinEvent -LogName "Microsoft-Windows-Networking-NetworkAtc/Operational" -MaxEvents 10  | where message -like "*Error*" | Select-Object -property @{name='TimeCreated'; expression={$_.TimeCreated.ToString("yyyy-MM-dd_HH:mm:ss")}},MachineName,LevelDisplayName,Message | Sort-Object TimeWritten -Descending | convertto-json

Get-WinEvent -LogName "Microsoft-Windows-Networking-NetworkAtc/Admin" -MaxEvents 10 

Get-WinEvent -LogName "Microsoft-Windows-Networking-NetworkAtc/Admin" -MaxEvents 10  | Select-Object -property @{name='TimeCreated'; expression={$_.TimeCreated.ToString("yyyy-MM-dd_HH:mm:ss")}},MachineName,LevelDisplayName,Message | Sort-Object TimeWritten -Descending | convertto-json

Stop-Transcript
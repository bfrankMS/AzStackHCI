if (!(Test-Path c:\temp)){mkdir c:\temp}
Start-Transcript c:\temp\DumpHCIInfo.log

"======Nics========" 
Get-NetAdapter
"------------------"
Get-NetAdapterHardwareInfo
"------------------"
Get-VMNetworkAdapter -ManagementOS | ft Name,IsManagementOs,SwitchName, MacAddress,Status,IPAddresses,*band*
"------------------"
Get-VMNetworkAdapter * | ft name,vmname,*band* 

"======Switch========"
Get-VMSwitch
Get-VMSwitch | fl *
"------------------"
Get-VMSwitchTeam
"------------------"
Get-VMNetworkAdapterTeamMapping -Name "*" -ManagementOS

"======RDMA & QoS========"
Get-NetAdapterRdma
Get-NetAdapterRdma -Name "*" | Where-Object -FilterScript { $_.Enabled } | fl *
"------------------"
Get-NetAdapterQos
"------------------"
Get-NetQosTrafficClass -Cimsession (Get-ClusterNode).Name | Select PSComputerName, Name, Priority, Bandwidth
Get-NetQosFlowControl
Get-NetQosPolicy

"======Hyper-V Host========"
Get-VMHost | fl *

"======Network ATC========"
Get-NetIntent | Format-Table IntentName, Scope,IntentType,NetAdapterNamesAsList, StorageVLANs,ManagementVLAN
Get-NetIntentStatus | Format-Table IntentName, Host, ProvisioningStatus, ConfigurationStatus

Get-NetIntentStatus -Globaloverrides

$intents | %{$_ | select-object -Property IntentName, AdapterAdvancedParametersOverride,RssConfigOverride,QosPolicyOverride,SwitchConfigOverride,IPOverride |convertto-json}

"======Nics advanced========"
Get-SmbBandwidthLimit
"------------------"
Get-NetAdapterSriov -Name "*" | ft Name,enabled, SwitchName,SriovSupport,NumVFs -AutoSize
"------------------"
Get-NetAdapterAdvancedProperty
"------------------"
Get-NetAdapterRss
"------------------"
Get-NetAdapterStatistics -Name "*"
Get-NetAdapterStatistics -Name "*" | Format-List -Property "*"
"------------------"

"======Eventlogs========"
Get-EventLog -list
"------------------"
Get-WinEvent -ListLog * | where {$_.RecordCount -gt 0}
"------------------"
Get-EventLog application -newest 20 -EntryType FailureAudit,Error,Warning
Get-EventLog application -newest 10 -EntryType FailureAudit,Error,Warning | Select-Object -property @{name='TimeWritten'; expression={$_.TimeWritten.ToString("yyyy-MM-dd_HH:mm:ss")}},MachineName,EntryType,Source,InstanceID,Message | Sort-Object TimeWritten -Descending | convertto-json
"------------------"
Get-EventLog system -newest 20 -EntryType FailureAudit,Error,Warning
Get-EventLog system -newest 10 -EntryType FailureAudit,Error,Warning | Select-Object -property @{name='TimeWritten'; expression={$_.TimeWritten.ToString("yyyy-MM-dd_HH:mm:ss")}},MachineName,EntryType,Source,InstanceID,Message | Sort-Object TimeWritten -Descending | convertto-json

"=============="
Stop-Transcript



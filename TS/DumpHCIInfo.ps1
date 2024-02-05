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

$intents = Get-NetIntent 
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
$HCILogs = @("system","application","AKSHCI","azshciarc","AzStackHciEnvironmentChecker","Microsoft-Windows-Health-Hci/Operational","Microsoft-AzureStack-HCI/Admin","Microsoft-AzureStack-HCI-AttestationService/Admin","Microsoft-Windows-Networking-NetworkAtc/Operational", "Microsoft-Windows-Networking-NetworkAtc/Admin")

foreach ($log in $HCILogs)
{
    Get-WinEvent -LogName "$log" -MaxEvents 10
    Get-WinEvent -LogName "$log" -MaxEvents 10  | Select-Object -property @{name='TimeCreated'; expression={$_.TimeCreated.ToString("yyyy-MM-dd_HH:mm:ss")}},MachineName,LevelDisplayName,Message | Sort-Object TimeWritten -Descending | convertto-json
}

"=============="
Stop-Transcript



if (!(Test-Path c:\temp)) { mkdir c:\temp }

$header = @"
host = $env:COMPUTERNAME
Time = $(Get-Date -Format "yyyy-MM-dd_HH:mm:ss")
whoami = $(whoami)
"@

$header | Out-File -FilePath "c:\temp\DumpHCIInfo.log"

$commands = @(
    @{
        Name = "Get-NetAdapter"; Command = { Get-NetAdapter }
    },
    @{
        Name = "Get-NetAdapterHardwareInfo"; Command = { Get-NetAdapterHardwareInfo }
    },
    @{
        Name = "Get-VMNetworkAdapter -ManagementOS"; Command = { Get-VMNetworkAdapter -ManagementOS | Format-Table Name, IsManagementOs, SwitchName, MacAddress, Status, IPAddresses, *band* }
    },
    @{
        Name = "Get-VMNetworkAdapter *"; Command = { Get-VMNetworkAdapter * | Format-Table name, vmname, *band* }
    },
    @{
        Name = "Get-VMSwitch"; Command = { Get-VMSwitch }
    },
    @{
        Name = "Get-VMSwitch | Format-List *"; Command = { Get-VMSwitch | Format-List * }
    },
    @{
        Name = "Get-VMSwitchTeam"; Command = { Get-VMSwitchTeam }
    },
    @{
        Name = "Get-VMNetworkAdapterTeamMapping -Name -ManagementOS"; Command = { Get-VMNetworkAdapterTeamMapping -Name "*" -ManagementOS }
    },
    @{
        Name = "Get-NetAdapterRdma"; Command = { Get-NetAdapterRdma }
    },
    @{
        Name = "Get-NetAdapterRdma -Name | Where-Object -FilterScript { $_.Enabled } | Format-List *"; Command = { Get-NetAdapterRdma -Name "*" | Where-Object -FilterScript { $_.Enabled } | Format-List * }
    },
    @{
        Name = "Get-NetAdapterQos"; Command = { Get-NetAdapterQos }
    },
    @{
        Name = "Get-NetQosTrafficClass -Cimsession (Get-ClusterNode).Name | Select-Object PSComputerName, Name, Priority, Bandwidth"; Command = { Get-NetQosTrafficClass -Cimsession (Get-ClusterNode).Name | Select-Object PSComputerName, Name, Priority, Bandwidth }
    },
    @{
        Name = "Get-NetQosFlowControl"; Command = { Get-NetQosFlowControl }
    },
    @{
        Name = "Get-NetQosPolicy"; Command = { Get-NetQosPolicy }
    },
    @{
        Name = "Get-VMHost | Format-List *"; Command = { Get-VMHost | Format-List * }
    },
    @{
        Name = "Get-NetIntent | Format-Table IntentName, Scope, IntentType, NetAdapterNamesAsList, StorageVLANs, ManagementVLAN"; Command = { Get-NetIntent | Format-Table IntentName, Scope, IntentType, NetAdapterNamesAsList, StorageVLANs, ManagementVLAN }
    },
    @{
        Name = "Get-NetIntentStatus | Format-Table IntentName, Host, ProvisioningStatus, ConfigurationStatus"; Command = { Get-NetIntentStatus | Format-Table IntentName, Host, ProvisioningStatus, ConfigurationStatus }
    },
    @{
        Name = "Get-NetIntentStatus -Globaloverrides"; Command = { Get-NetIntentStatus -Globaloverrides }
    },
    @{
        Name = "Get-SmbBandwidthLimit"; Command = { Get-SmbBandwidthLimit }
    },
    @{
        Name = "Get-NetAdapterSriov -Name | Format-Table Name, enabled, SwitchName, SriovSupport, NumVFs -AutoSize"; Command = { Get-NetAdapterSriov -Name "*" | Format-Table Name, enabled, SwitchName, SriovSupport, NumVFs -AutoSize }
    },
    @{
        Name = "Get-NetAdapterAdvancedProperty"; Command = { Get-NetAdapterAdvancedProperty }
    },
    @{
        Name = "Get-NetAdapterRss"; Command = { Get-NetAdapterRss }
    },
    @{
        Name = "Get-NetAdapterStatistics -Name"; Command = { Get-NetAdapterStatistics -Name "*" }
    },
    @{
        Name = "Get-NetAdapterStatistics -Name | Format-List -Property "; Command = { Get-NetAdapterStatistics -Name "*" | Format-List -Property "*" }
    },
    @{
        Name = "Get-EventLog -list"; Command = { $HCILogs = @("system", "application", "AKSHCI", "azshciarc", "AzStackHciEnvironmentChecker", "Microsoft-Windows-Health-Hci/Operational", "Microsoft-AzureStack-HCI/Admin", "Microsoft-AzureStack-HCI-AttestationService/Admin", "Microsoft-Windows-Networking-NetworkAtc/Operational", "Microsoft-Windows-Networking-NetworkAtc/Admin")

            foreach ($log in $HCILogs) {
                Get-WinEvent -LogName "$log" -MaxEvents 10
                Get-WinEvent -LogName "$log" -MaxEvents 10  | Select-Object -Property @{name = 'TimeCreated'; expression = { $_.TimeCreated.ToString("yyyy-MM-dd_HH:mm:ss") } }, MachineName, LevelDisplayName, Message | Sort-Object TimeWritten -Descending | ConvertTo-Json
            }
        }
    },
    @{
        Name = "Get-ClusterLog "; Command = { Get-ClusterLog -TimeSpan 5 -Destination 'c:\temp\' }
    }
)

foreach ($command in $commands) {
    <# $currentItemName is the current item #>
    "---> {0}" -f $command.Name 
    "---> {0}" -f $command.Name | Out-File -FilePath "c:\temp\DumpHCIInfo.log" -Append
    Invoke-Command -ScriptBlock $($command.Command) | Out-File -FilePath "c:\temp\DumpHCIInfo.log" -Append 
}



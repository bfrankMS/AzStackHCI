# AzStack HCI - bfrank's Best Practices Checklist Draft 0.1

> Note: This compilation is not complete and may contain errors or superfluous information. Feel free to contribute.

## Example Vendor Deployment Guides
The contain a lot HW specific but also generic settings and best practices. Worth checking - even if your HW is different.
- [HPE: Implementing Azure Stack HCI OS using HPE ProLiant servers technical white paper](https://www.hpe.com/psnow/doc/a50004375enw)
- [Lenovo: S2D Deployment Guide](https://lenovopress.lenovo.com/lp0064-microsoft-storage-spaces-direct-s2d-deployment-guide)
- [Dell: S2D Deployment Guide](https://downloads.dell.com/solutions/general-solution-resources/White%20Papers/DellEMCMicrosoft_StorageSpacesDirect_ReadyNode_PowerEdgeR740xdR640-Scalable-DG.pdf)

## Physical Switch:
With AzStack HCI we have 3 traffic classes: **Management** (e.g. Cluster internal or to DC), **Compute** (VMs network talk), **Storage** (SMB direct (RDMA) | S2D traffic)
- Make sure the switch you choose does work for connected traffic class! [Network switches for Azure Stack HCI](https://learn.microsoft.com/en-us/azure-stack/hci/concepts/physical-network-requirements?tabs=22H2%2C20-21H2reqs)
- (Storage) RDMA switchports set higher MTU size
- (Storage) Do PFC / DCB settings as per vendor documentation see e.g. [HPE], [Lenovo]  
  
[HPE]: https://www.hpe.com/psnow/doc/a50004375enw
[Lenovo]: https://lenovopress.lenovo.com/lp0064-microsoft-storage-spaces-direct-s2d-deployment-guide

## BIOS:
**Rule of thumb: follow your vendors 'S2D | HCI deployment guide'.**  
These probably include settings similar to:  
- Boot Mode - UEFI
- Enable Virtualization Mode 
- Enable SR-IOV
- Due to EU regulations your system might be set to run power- and perf- capped: Check and change if required: e.g. System profile | CPU Mode to High or "Virtualization Max Performance" -> refer to your vendors documentation + [Perf tuning for low latency]
- Enable secure boot.
- When having multiple physical NICs + multiple CPUs: You might want to use (fast) PCIe lanes that are served by different CPUs (to split load) 
  
[Perf tuning for low latency]: https://learn.microsoft.com/en-us/windows-server/networking/technologies/network-subsystem/net-sub-performance-tuning-nics?source=recommendations#bkmk_low


## OS:
### Network
- Before configure host networking make sure the **firmware** & **drivers** for all NICs are update. Use your vendors supported way.
- (**Storage**) Enable jumbo frames e.g.  
  `Set-NetAdapterAdvancedProperty -Name $StorageAdapter1Name -DisplayName "Jumbo Packet" -RegistryValue 9014`
- (**Storage**) Use Qos Poliy and RDMA (required for [RoCE](https://learn.microsoft.com/en-us/previous-versions/windows/it-pro/windows-server-2012-r2-and-2012/dn583822(v=ws.11)) - recommended for [iWARP](https://learn.microsoft.com/en-us/previous-versions/windows/it-pro/windows-server-2012-r2-and-2012/dn583825(v=ws.11))  )
--->consult your vendors deployment guide.

- (applies to **Compute**, Management, Storage) Create the set switch depending on what the HW supports e.g.  
  `New-VMSwitch -EnableEmbeddedTeaming  $true [-EnableIov $true] [-EnablePacketDirect $true] [-Minimumbandwidthmode Weight]`  
  (Packet Direct https://learn.microsoft.com/en-us/windows-hardware/drivers/network/introduction-to-ndis-pdpi)  
  ---> Consult vendor documentation.

- (**Storage**) When using switched storage networks and multiple switches: Avoid inter switch communication for storage traffic (i.e. avoid SW1:SMB1 <---interconnect---> SW2:SMB1) by mapping your virtual storage adapters to physical adapters plugged into the correct switch. E.g.  
  `Set-VMNetworkAdapterTeamMapping -VMNetworkAdapterName "$StorageAdapter1Name" -ManagementOS -PhysicalNetAdapterName "$physicalNic1Name" -Verbose`

- (**Storage**) Do a [Test-RDMA](./Test-RDMA/howto_test-rdma.md) + [Test-RDMA.ps1](https://github.com/microsoft/SDN/blob/master/Diagnostics/Test-Rdma.ps1) before going into production.
  
### Updating the page file settings
To help ensure that the active memory dump is captured if a fatal system error occurs, allocate sufficient space for the page file. E.g. Dell Technologies recommends allocating at least 50 GB plus the size of the CSV block cache.

### Storage 
- Consider Reduced networking performance after you enable SMB Encryption or SMB Signing
https://learn.microsoft.com/en-us/troubleshoot/windows-server/networking/reduced-performance-after-smb-encryption-signing?source=recommendations

## Cluster:
- VMs should not talk on the management network.
- Have additional networks for cluster to cluster communication (i.e. Heartbeat. Not just one)
- Configure cluster witness.
- Create at least one CSV per node. ( CSVFS_ReFS as filesystem)
- Make sure your CSVs uses the proper resiliency & performance option for your workload. [Plan volumes]

- (optional) Consider using jumbo frames on the Live migration network.
- Remove the host management network from live migration - or de-priotize the host management network for live migration - e.g.:
```powershell
$clusterResourceType = Get-ClusterResourceType -Name 'Virtual Machine'
$hostNetworkID = Get-ClusterNetwork | Where-Object { $_.Address -eq '172.16.102.0' } | Select-Object -ExpandProperty ID
$otherNetworkID = (Get-ClusterNetwork).Where({$_.ID -ne $hostnetworkID}).ID
$newMigrationOrder = ($otherNetworkID + $hostNetworkID) -join ';'
Set-ClusterParameter -InputObject $clusterResourceType -Name MigrationNetworkOrder -Value $newMigrationOrder
```
- (optional) [...enable CSV cache](https://techcommunity.microsoft.com/t5/failover-clustering/how-to-enable-csv-cache/ba-p/371854) for read-intensive workloads:
`(Get-Cluster).BlockCacheSize = 512`
- (optional) If you consider [Using Storage Spaces Direct in guest virtual machine clusters](https://learn.microsoft.com/en-us/windows-server/storage/storage-spaces/storage-spaces-direct-in-vm)  
  To give greater resiliency to possible VHD / VHDX / VMDK storage latency in guest clusters, increase the Storage Spaces I/O timeout value:
```PowerShell
Set-ItemProperty -Path HKLM:\SYSTEM\CurrentControlSet\Services\spaceport\Parameters -Name HwTimeout -Value 0x00002710 -Verbose
# 0x00002710 (HEX) = 10000 (DEX) => 10 secs
# Restart-Computer -Force
```  
[Plan volumes]: https://learn.microsoft.com/en-us/azure-stack/hci/concepts/plan-volumes#with-four-or-more-servers

## Advanced & Experimental

### Networking
- Have a look at [Performance tuning for low-latency packet processing](https://learn.microsoft.com/en-us/windows-server/networking/technologies/network-subsystem/net-sub-performance-tuning-nics?source=recommendations#bkmk_low) and the remainder of the article and consider tuning.
- Check your RSS and VMQ settings and consider tuning of those: 
  - basically check that RSS is enabled, your Nics are NUMA node aligned (i.e. use the CPU that serving the NICs PCIe bus), use jumbo frames, VMMQ is enabled, and your vNics (especially host vnics e.g. vSMB1, vREPL,...) are affinitized to the right pNIC.  
https://learn.microsoft.com/en-us/windows-hardware/drivers/network/introduction-to-receive-side-scaling
https://www.darrylvanderpeijl.com/windows-server-2016-networking-optimizing-network-settings/ 
https://www.broadcom.com/support/knowledgebase/1211161326328/rss-and-vmq-tuning-on-windows-servers
https://learn.microsoft.com/en-us/windows-hardware/drivers/network/vmmq-send-and-receive-processing

### Storage Replica
- personal tests have shown about 10% improvement on througput (read / write) impact on SR 
[Performance tuning for SMB file servers](https://learn.microsoft.com/en-us/windows-server/administration/performance-tuning/role/file-server/smb-file-server)
```PowerShell
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Session Manager\Executive' -Name AdditionalCriticalWorkerThreads -Value 0x00000140 -Verbose
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Session Manager\Executive' -Name AdditionalDelayedWorkerThreads -Value 0x00000140 -Verbose
```
(reboot)
(tried 0x40 before: did not show impact on my system.)




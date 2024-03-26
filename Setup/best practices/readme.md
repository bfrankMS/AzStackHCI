# AzStack HCI - bfrank's compilation of best practices found - Checklist Draft 0.1

> Warning: This is a compilation of stuff found on the internet + personal habits. It is not complete and might contain errors or superfluous information. No warranties. Use for brainstorming and feel free to contribute.

## Example Vendor Deployment Guides
The contain a lot HW specific but also generic settings and best practices. Worth checking - even if your HW is different.
- [HPE: Implementing Azure Stack HCI OS using HPE ProLiant servers technical white paper](https://www.hpe.com/psnow/doc/a50004375enw)
- [Lenovo: S2D Deployment Guide](https://lenovopress.lenovo.com/lp0064-microsoft-storage-spaces-direct-s2d-deployment-guide)
- [Dell: S2D Deployment Guide](https://downloads.dell.com/solutions/general-solution-resources/White%20Papers/DellEMCMicrosoft_StorageSpacesDirect_ReadyNode_PowerEdgeR740xdR640-Scalable-DG.pdf)

## Physical Switch:
With AzStack HCI we have 3 traffic classes: **Management** (e.g. Cluster internal or to DC), **Compute** (VMs network talk), **Storage** (SMB direct (RDMA) | S2D traffic)
- Make sure the switch you choose does work for connected traffic class! [Network switches for Azure Stack HCI](https://learn.microsoft.com/en-us/azure-stack/hci/concepts/physical-network-requirements?tabs=22H2%2C20-21H2reqs)
- (**Storage**) RDMA switchports set higher MTU size
- (**Storage**) Do PFC / DCB settings as per vendor deployment guide see e.g. [HPE], [Lenovo]  
  
[HPE]: https://www.hpe.com/psnow/doc/a50004375enw
[Lenovo]: https://lenovopress.lenovo.com/lp0064-microsoft-storage-spaces-direct-s2d-deployment-guide

## Hardware 
- **Rule of thumb**: **Buy an integrated system or at least validated nodes (it's tested, certified)** [Azure Stack HCI Solutions]  
  (This does not mean that you could not build a working HCI - you may save some bucks on HW but you will invest (substancial) time(==money) learning ;-) )
- You need a Host Bus Adapter (HBA) - not a RAID controller for your SSDs, HDDs (HDDs? Can do - but I wouldn't). (nowadays seen controllers that can do both: RAID for OS & HBA for S2D) -> make sure your's is supported. -> ask vendor and check [Storage Spaces Direct hardware requirements](https://learn.microsoft.com/en-us/windows-server/storage/storage-spaces/storage-spaces-direct-hardware-requirements)
- Never use consumer grade SSDs - just [Don't do it] - performance will '*su.k*' (SATA is ok but it has to be DC ready i.e. you **require 'Power-Loss Protection'** )
- How many disks you need to buy? (or *perf + resiliency impacts storage efficiency*) **Rule of thumb: Have your savvy vendor help you with right sizing** + Do the plausibility check: [Storage Spaces Direct Calculator (preview)](https://aka.ms/s2dcalc)  
  - >Beware: That vendors use Terrabyte to express a device capacity - however many OSes show e.g. Tebibyte (1TB = 0.91TiB) - beware with what your are calculating - not to run short!
- Choose only [NICs that have the required certifications](https://learn.microsoft.com/en-us/azure-stack/hci/concepts/host-network-requirements) [Windows Server Catalog]  

[Azure Stack HCI Solutions]: https://hcicatalog.azurewebsites.net/#/catalog
[Don't do it]: https://techcommunity.microsoft.com/t5/storage-at-microsoft/don-t-do-it-consumer-grade-solid-state-drives-ssd-in-storage/ba-p/425914
[Windows Server Catalog]: https://www.windowsservercatalog.com/

## BIOS:
**Rule of thumb: follow your vendors 'S2D | HCI deployment guide'.**  
These probably include settings similar to:  
- Boot Mode - UEFI
- Enable Virtualization Mode 
- Enable SR-IOV
- Due to EU regulations your system might be set to run power- and perf- capped: Check and change if required: e.g. System profile | CPU Mode to High or "Virtualization Max Performance" -> refer to your vendor's deployment guide + [Perf tuning for low latency]
- Enable secure boot.
- When having multiple physical NICs + multiple CPUs: You might want to use (fast) PCIe lanes that are served by different CPUs (to split load) 
  
[Perf tuning for low latency]: https://learn.microsoft.com/en-us/windows-server/networking/technologies/network-subsystem/net-sub-performance-tuning-nics?source=recommendations#bkmk_low


## OS:
Do **not** update! This will be part of the installation.
### Network
In 23H2 most of the networking settings will be done for you (some based on your input). We have 3 networks to care about:  
1. **Management** - e.g. cluster communication, host to domain controller traffic, internet access, DNS,...
2. **Compute** - for the VMs to talk to the outside world.
3. **Storage** - for S2D i.e. the network traffic to provide storage redundancy (iwarp, RoCE, RoCEv2)
  
For these networks and the adapters there are some best practices to consider: 
- Before configure host networking make sure the **firmware** & **drivers** for all NICs are update. Use your vendors supported way.
- (**Management, Compute, Storage**) Jumbo frames are the default. Make sure these are working with the switches that adapters are attached to.  
- Configure just one network adapter to talk to the internet. With DNS, DG, single IP. 
- Remove IPv6 from all network adapters when not configured.
- Rename network adapters consistently accross all cluster nodes for their purpose: e.g.
```PowerShell
Rename-NetAdapter -InterfaceDescription 'Intel(R) Ethernet Network Adapter E810-XXV-2' -NewName "Storage1"
```
- (**Storage**) When switchless Make sure adapters are labeled and cross cabled correctly. You may consider looking at the nics MAC address to map interface description with physical port at the back of the server. e.g.  
```cmd
PS C:\Users\Administrator.MYAVD\Documents> get-netadapter

Name                      InterfaceDescription                    ifIndex Status       MacAddress             LinkSpeed
----                      --------------------                    ------- ------       ----------             ---------
COMP2                     Intel(R) Ethernet Connection X722 fo...      15 Up           04-7B-CB-8A-45-FD        10 Gbps
SMB1                      Intel(R) Ethernet Network Adapter E8...      14 Up           B4-96-91-BA-22-54        25 Gbps
NIC1_HCIMX1               Intel(R) I350 Gigabit Network Connec...      13 Not Present  08-3A-88-FA-C5-CE          0 bps
SMB2                      Intel(R) Ethernet Network Adapter ...#2      11 Up           B4-96-91-BA-22-55        25 Gbps
COMP1                     Intel(R) Ethernet Connection X722 ...#2       9 Up           04-7B-CB-8A-45-FC        10 Gbps
Ethernet                  IBM USB Remote NDIS Network Device            6 Not Present  06-7B-CB-8A-46-02          0 bps
NIC2_HCIMX1               Intel(R) I350 Gigabit Network Conn...#2       4 Not Present  08-3A-88-FA-C5-CF          0 bps
```
- Disable DHCP, DNS registration, and IPv6 on all other adapters e.g.  
```PowerShell
$SMB2NetAdapterName = "Storage2"
Set-NetIPInterface -InterfaceAlias $SMB2NetAdapterName -Dhcp Enabled -Verbose
Start-Sleep 3
Set-NetIPInterface -InterfaceAlias $SMB2NetAdapterName -Dhcp Disabled -Verbose
Set-DnsClient -InterfaceAlias $SMB2NetAdapterName -RegisterThisConnectionsAddress $false
Disable-NetAdapterBinding -InterfaceAlias $SMB2NetAdapterName -ComponentID ms_tcpip6      #disable IPv6  
```
- Rename adapters that should not be used with a unique value - e.g. the host's name and disable them:  
```PowerShell
$nic = get-netadapter -InterfaceDescription 'Intel(R) I350 Gigabit Network Connection'
Rename-NetAdapter -InputObject $nic -NewName $("$($nic.Name)" + "_" + $env:COMPUTERNAME)
Disable-NetAdapter -InputObject $nic -Verbose
```
```
NIC1_HCIMX1               Intel(R) I350 Gigabit Network Connec...      13 Not Present  08-3A-88-FA-C5-CE          0 bps
```
 
- (**Storage**) When this network is switched be aware that Qos Policies and RDMA will be used (required for [RoCE](https://learn.microsoft.com/en-us/previous-versions/windows/it-pro/windows-server-2012-r2-and-2012/dn583822(v=ws.11)) - recommended for [iWARP](https://learn.microsoft.com/en-us/previous-versions/windows/it-pro/windows-server-2012-r2-and-2012/dn583825(v=ws.11))  )
--->make sure switches are configured to support it! Consult your vendor's deployment guide.
- (**Storage**) Do a [Test-RDMA](./Test-RDMA/howto_test-rdma.md) + [Test-RDMA.ps1](https://github.com/microsoft/SDN/blob/master/Diagnostics/Test-Rdma.ps1) before going into production.
  

### Storage 
- Consider [Reduced networking performance after you enable SMB Encryption or SMB Signing](https://learn.microsoft.com/en-us/troubleshoot/windows-server/networking/reduced-performance-after-smb-encryption-signing?source=recommendations)
- Run a [VMFleet 2.0](https://techcommunity.microsoft.com/t5/azure-stack-blog/vmfleet-2-0-quick-start-guide/ba-p/2824778) test to do a performance baseline of your storage before putting workload on. 


## Cluster:
- VMs should not talk on the management network.
- Have additional networks for cluster to cluster communication (i.e. Heartbeat. Not just one)
- Configure cluster witness (will be done for you)
- Create at least one CSV per node. ( CSVFS_ReFS as filesystem)
- Make sure your CSVs uses the proper resiliency & performance option for your workload. [Plan volumes]
- Remove the host management network from live migration - or de-priotize the host management network for live migration - e.g.:
```powershell
$clusterResourceType = Get-ClusterResourceType -Name 'Virtual Machine'
$hostNetworkID = Get-ClusterNetwork | Where-Object { $_.Address -eq '172.16.102.0' } | Select-Object -ExpandProperty ID
$otherNetworkID = (Get-ClusterNetwork).Where({$_.ID -ne $hostnetworkID}).ID
$newMigrationOrder = ($otherNetworkID + $hostNetworkID) -join ';'
Set-ClusterParameter -InputObject $clusterResourceType -Name MigrationNetworkOrder -Value $newMigrationOrder
```
[Plan volumes]: https://learn.microsoft.com/en-us/azure-stack/hci/concepts/plan-volumes#with-four-or-more-servers

## Advanced & Experimental

### Networking
- Have a look at [Performance tuning for low-latency packet processing](https://learn.microsoft.com/en-us/windows-server/networking/technologies/network-subsystem/net-sub-performance-tuning-nics?source=recommendations#bkmk_low) and the remainder of the article and consider tuning.
- (**Storage** network) Test if reducing | disabling interrupt moderation reduces latencies: [Interrupt Moderation (IM)](https://learn.microsoft.com/en-us/windows-server/networking/technologies/hpn/hpn-hardware-only-features#interrupt-moderation-im)
- Check your RSS and VMQ settings and consider tuning of those: 
  - basically check that RSS is enabled, your Nics are NUMA node aligned (i.e. use the CPU that serving the NICs PCIe bus), use jumbo frames, VMMQ is enabled, and your vNics (especially host vnics e.g. vSMB1, vREPL,...) are affinitized to the right pNIC.  
https://learn.microsoft.com/en-us/windows-hardware/drivers/network/introduction-to-receive-side-scaling  
https://www.darrylvanderpeijl.com/windows-server-2016-networking-optimizing-network-settings/ 
https://www.broadcom.com/support/knowledgebase/1211161326328/rss-and-vmq-tuning-on-windows-servers
https://learn.microsoft.com/en-us/windows-hardware/drivers/network/vmmq-send-and-receive-processing






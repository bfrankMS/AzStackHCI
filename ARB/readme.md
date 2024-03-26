# Important: Deprecated. Just For History

**If you want use** [Azure Arc VM management?](https://learn.microsoft.com/en-us/azure-stack/hci/manage/azure-arc-vm-management-overview) - **make sure you are using Azure Stack HCI, version 23H2!** 
With this version of AzStackHCI - Azure Arc VM management setup is included in the whole HCI setup, i.e. you do not need to use these scripts deposited here.

## Content related to the Azure Arc Resource Bridge (ARB) on AzStack 22H2
>Note: Azure Arc Resource Bridge was never released on 22H2 - it was first officially launched on 23H2. Since Feb 2024 functionality (on 22H2) was limited. Over the time I expect it to go completely offline for 22H2.

## or the thing that allows you to provision VMs onto your HCI via the Azure Portal
[What is Azure Arc resource bridge (preview)?](https://learn.microsoft.com/en-us/azure/azure-arc/resource-bridge/overview)

Contents:  
- [22H2 ARM template for a single VM (ARB) deployment to HCI](arb-vm.json) -> hit [deploy](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FbfrankMS%2FAzStackHCI%2Fmain%2FARB_22H2%2Farb-vm.json) it to Azure.
- [22H2 ARM template for a multi VM deployment onto HCI](arb-vmloop.json) -> hit [deploy](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FbfrankMS%2FAzStackHCI%2Fmain%2FARB_22H2%2Farb-vmloop.json) it to Azure.
<# 

  This script should install AKS in combination with the Azure Resource Bridge on HCI 
  
  Warning: don't run from top to bottom all at once....
  run in snippets. 
  before you execute code - change names, paths (e.g. CSV location), and most important adopt to your IP address ranges 

    References:
    1) Installing AKS with PS: https://learn.microsoft.com/en-us/azure-stack/aks-hci/aks-hci-evaluation-guide-2b
    2) Installing ARB with PS: https://learn.microsoft.com/en-us/azure-stack/hci/manage/deploy-arc-resource-bridge-using-command-line?tabs=for-static-ip-address

  #>

#region Snippet 1: Installing required PS dependencies when needed
Set-PSRepository -Name "PSGallery" -InstallationPolicy Trusted
Install-PackageProvider -Name NuGet -Force 
Install-Module -Name PowershellGet -Force -Confirm:$false -SkipPublisherCheck 
#Remove-Module PowerShellGet
Exit
#endregion 

#region Snippet 2: Installing AKSHCI module to powershell AKS onprem
#start powershell  #to load new powershellget module
Install-Module -Name AksHci -Repository PSGallery -Force -Confirm:$false -SkipPublisherCheck -AcceptLicense
Get-Command -Module AksHci
#endregion

#region Snippet 3: Get-Option helper function to provide menu
function Get-Option ($cmd, $filterproperty) {
  $items = @("")
  $selection = $null
  $filteredItems = @()
  Invoke-Expression -Command $cmd | Sort-Object $filterproperty | ForEach-Object -Begin { $i = 0 } -Process {
    $items += "{0}. {1}" -f $i, $_.$filterproperty
    $i++
  } 
  $filteredItems += $items | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
  $filteredItems | Format-Wide { $_ } -Column 4 -Force | Out-Host
  #$filteredItems.Count
  #$filteredItems | Out-Host
  do {
    $r = [int]::Parse((Read-Host "Select by number"))
    $selection = $filteredItems[$r] -split "\.\s" | Select-Object -Last 1
    if ([String]::IsNullOrWhiteSpace($selection)) { Write-Host "You must make a valid selection" -ForegroundColor Red }
    else {
      Write-Host "Selecting $($filteredItems[$r])" -ForegroundColor Green
    }
  }until (!([String]::IsNullOrWhiteSpace($selection)))
    
  return $selection
}
#endregion

#region Snippet 4: Logon to Azure, select right subscription, register resource provider
Connect-AzAccount -UseDeviceAuthentication

#selecting correct subscription
$sub = Get-Option "Get-AzSubscription" "Name" # alternatively you can choose "SubscriptionID" if you a
Set-AzContext $sub

#Register Resource provider
Register-AzResourceProvider -ProviderNamespace Microsoft.Kubernetes
Register-AzResourceProvider -ProviderNamespace Microsoft.KubernetesConfiguration
#endregion

#region Snippet 5: Prepare AKS install

$VerbosePreference = "Continue"
Initialize-AksHciNode # Important: Run on each node!!!!!

#selecting hyper-v vm switch for kubernetes vms.
$vSwitchName = Get-Option "Get-VMSwitch" "Name"

#k8s node networking pools
$k8sNodeIpPoolStart = "192.168.177.2"   # Kubernetes node VM IP pool - used to allocate IP addresses to Kubernetes nodes virtual machines to enable communication between Kubernetes nodes
$k8sNodeIpPoolEnd = "192.168.177.20"    # will limit the # of Kubernetes nodes you can use
$vipPoolStart = "192.168.177.21"        # Virtual IP pool - used to allocate IP addresses to the Kubernetes cluster API server.
$vipPoolEnd = "192.168.177.40"          # https://docs.microsoft.com/en-us/azure-stack/aks-hci/concepts-node-networking

$ipAddressPrefix = "192.168.177.0/24" 
$gateway = "192.168.177.1"        # your router to get to the internet
$dnsServers = "192.168.177.200"   # "IP1,IP2"     # this is a domain controller (with DNS) role - as a computer object is created in AD -> you can precreate this in AD and specify it in  'Set-AksHciConfig' -> https://learn.microsoft.com/en-us/azure-stack/aks-hci/prestage-cluster-service-host-create#step-4-configure-your-deployment-with-the-prestaged-cluster-service-objects-and-dns-records
$cloudservicecidr = "192.168.177.203/24"  #a free IP to be assigned for the clustered generic service that will be created.
#$vlanid = 1234 # not using it in my environment but you may want to
$csv_path = "c:\clusterstorage\CSV1"

#static IP
$vnet = New-AksHciNetworkSetting -name myaksnetwork -vSwitchName $vSwitchName `
  -k8sNodeIpPoolStart $k8sNodeIpPoolStart `
  -k8sNodeIpPoolEnd $k8sNodeIpPoolEnd `
  -vipPoolStart $vipPoolStart `
  -vipPoolEnd $vipPoolEnd `
  -ipAddressPrefix $ipAddressPrefix `
  -gateway $gateway `
  -dnsServers $dnsServers #domain + cluster DNSl  
  # -vlanid $vlanid

  <# snip until here #>

Set-AksHciConfig -imageDir "$csv_path\imageDir" -workingDir "$csv_path\workingDir" -cloudConfigLocation "$csv_path\cloudConfig" -vnet $vnet -cloudservicecidr $cloudservicecidr

$subscription = Get-AzContext

Write-Host "Selecting RG for registration" -ForegroundColor Green
$RG = Get-Option "Get-AzResourceGroup" "ResourceGroupName" 
#endregion

#region Snippet 6: Install AKS onprem
  # $token = Get-AzAccessToken # seems not to work at the moment.
  # Set-AksHciRegistration -subscriptionId $($subscription.Subscription.Id) -resourceGroupName $RG -ArmAccessToken $token.token -GraphAccessToken $token.token -AccountId $token.UserId   #should not give an auth prompt takes the user that logged on to azure subscription
  Set-AksHciRegistration -subscriptionId $($subscription.Subscription.Id) -resourceGroupName $RG    #gives a prompt
  Install-AksHci -Verbose

#endregion

#region (optional) To create a workload K8s cluster
$FormatEnumerationLimit = -1

Get-AksHciKubernetesVersion
(Get-Command New-AksHciCluster).Parameters.Values | Select-Object Name


$aksHciClusterName = "myk8s-wrkloadclus-$(Get-Random -Minimum 100 -Maximum 999)"

New-AksHciCluster -Name $aksHciClusterName -nodeCount 1 -osType linux -primaryNetworkPlugin calico 

Get-akshcicredential -name $aksHciClusterName -Confirm:$false
Get-ChildItem $env:userprofile\.kube

enable-akshciarcconnection -name $aksHciClusterName
#endregion

#region Snippet 7: Will install Azure CLI on node (if not there already and set the path envrionment variable)
  start-bitstransfer https://aka.ms/installazurecliwindows ".\AzureCLI.msi" -Priority High -RetryInterval 60  -Verbose -SecurityFlags 0,0,0 -TransferPolicy Always #faster
  Start-Process msiexec.exe -Wait -ArgumentList '/I AzureCLI.msi /passive /lvx* c:\temp\azcli.msi.log' 
  #Remove-Item .\AzureCLI.msi
  #add path as environment var.
  $env:Path += ";C:\Program Files (x86)\Microsoft SDKs\Azure\CLI2\wbin"
  [Environment]::SetEnvironmentVariable("Path", $env:Path,"User")
#endregion

#region Snippet 8: Prepare Azure Resource Bridge installation
    Write-Host -ForegroundColor green "Prepare Azure Resource Bridge installation"
    # https://docs.microsoft.com/en-us/azure-stack/hci/manage/deploy-arc-resource-bridge-using-command-line

    # Install-Module -Name Moc -Repository PSGallery -AcceptLicense -Force #1.0.24 - should be there already
    # update-module Moc

    #variables
    $vSwitchName = Get-Option "Get-VMSwitch" "Name"

    $SubscriptionId = $((Get-AzContext).Subscription.Id)

    $resource_group = $RG     #to use the kubernetes RG or do use any "<pre-created resource group in Azure>"

    $Location = "westeurope" # must be a ARB supported region  Available regions include 'eastus', 'eastus2euap' and 'westeurope'
    $customloc_name = "HCIonprem"  #You may want to change this.
    
    $ARBPath = "$csv_path\ResourceBridge"
    
    $resource_name = ((Get-AzureStackHci).AzureResourceName) + "-arcbridge"
    if (!(Test-Path "$ARBPath"))
    {
        Write-Output "Create ARB path"
        mkdir "$ARBPath"
    }
    
    #make sure you have the 
    # make sure your node networking pool settings differ from above - otherwhise you might have duplicate IPs!!!
    $arcbridge_k8sNodeIpPoolStart = "192.168.177.41"   # Kubernetes node VM IP pool - used to allocate IP addresses to Kubernetes nodes virtual machines to enable communication between Kubernetes nodes
    $arcbridge_k8sNodeIpPoolEnd = "192.168.177.50"    # will limit the # of Kubernetes nodes you can use
    $arcbridge_vipPoolStart = "192.168.177.51"        # Virtual IP pool - used to allocate IP addresses to the Kubernetes cluster API server.
    $arcbridge_vipPoolEnd = "192.168.177.59"          # https://docs.microsoft.com/en-us/azure-stack/hci/manage/deploy-arc-resource-bridge-using-command-line
    
    $ipAddressPrefix = "192.168.177.0/24"
    $gateway = "192.168.177.1"
    $dnsServers = "192.168.177.200"
    $controlPlaneIP = "192.168.177.204"
  
    
    Initialize-MocNode
    Install-Module -Name ArcHci -Force -Confirm:$false -SkipPublisherCheck -AcceptLicense  # Important: Should be >= 0.2.10
    Get-Module -Name ArcHci -ListAvailable

    New-ArcHciConfigFiles -subscriptionID $SubscriptionId -location $location -resourceGroup $resource_group `
        -resourceName $resource_name -workDirectory "$ARBPath" `
        -vipPoolStart $arcbridge_vipPoolStart -vipPoolEnd $arcbridge_vipPoolEnd `
        -dnsServers $dnsServers -vSwitchName $vSwitchName -gateway $gateway -ipAddressPrefix $ipAddressPrefix -vnetName myaksnetwork `
        -k8sNodeIpPoolStart $arcbridge_k8sNodeIpPoolStart -k8sNodeIpPoolEnd $arcbridge_k8sNodeIpPoolEnd -controlPlaneIP $controlPlaneIP #-vlanid

        #this also creates a token file for the ARB

    #run some AZ cli commands provision subscription and download az cli extensions
    az login --use-device-code
    az account set --subscription $SubscriptionId
    
    az extension remove --name arcappliance --verbose
    az extension remove --name connectedk8s --verbose
    az extension remove --name k8s-configuration --verbose
    az extension remove --name k8s-extension --verbose
    az extension remove --name customlocation --verbose
    az extension remove --name azurestackhci --verbose
    
    az extension add --upgrade --name arcappliance --verbose
    az extension add --upgrade --name connectedk8s --verbose
    az extension add --upgrade --name k8s-configuration --verbose
    az extension add --upgrade --name k8s-extension --verbose
    az extension add --upgrade --name customlocation --verbose
    az extension add --upgrade --name azurestackhci --verbose
    
    az provider register --namespace Microsoft.Kubernetes
    az provider register --namespace Microsoft.KubernetesConfiguration
    az provider register --namespace Microsoft.ExtendedLocation
    az provider register --namespace Microsoft.ResourceConnector
    az provider register --namespace Microsoft.AzureStackHCI
    az feature register --namespace Microsoft.ResourceConnector --name Appliances-ppauto
    az provider register -n Microsoft.ResourceConnector

#endregion

#region Snippet 9: Prepare: dowload appliance to ResourceBridge folder
    az arcappliance prepare hci --config-file "$ARBPath\hci-appliance.yaml" --verbose
    #----> downloading (puts it into the workingdir)
#endregion 

#region Snippet 10: Deploy arc bridge
    az arcappliance deploy hci --config-file  "$ARBPath\hci-appliance.yaml" --outfile "$env:USERPROFILE\.kube\config"

    <# Sucess should look like

PS C:\Users\Administrator.CONTOSO> az arcappliance deploy hci --config-file  "$ARBPath\hci-appliance.yaml" --outfile "$env:USERPROFILE\.kube\config"
Command group 'arcappliance deploy' is in preview and under development. Reference and support levels: https://aka.ms/CLI_refstatus
Creating the appliance...

2022-05-05T13:22:32+02:00       INFO    azurestackhciProvider: Ensure Prerequisites
2022-05-05T13:22:32+02:00       INFO    azurestackhciProvider: Reconciling Group
2022-05-05T13:22:32+02:00       INFO    azurestackhciProvider: Reconciling Keyvault
2022-05-05T13:22:32+02:00       INFO    azurestackhciProvider: Reconciling Virtual Network
2022-05-05T13:22:32+02:00       INFO    azurestackhciProvider: Reconciling Load Balancer
2022-05-05T13:22:32+02:00       INFO    azurestackhciProvider: Reconciling Load Balancer resource
2022-05-05T13:22:32+02:00       INFO    azurestackhciProvider: Reconciling Control Plane Endpoint
2022-05-05T13:22:32+02:00       INFO    azurestackhciProvider: Reconciled Control Plane Endpoint: 192.168.177.204
2022-05-05T13:23:02+02:00       INFO    azurestackhciProvider: CloudInit
2022-05-05T13:23:04+02:00       INFO    azurestackhciProvider: DeployAppliance
2022-05-05T13:23:34+02:00       INFO    azurestackhciProvider: Waiting for Appliance VM IP address
2022-05-05T13:23:34+02:00       INFO    azurestackhciProvider: Appliance IP is 192.168.177.41
2022-05-05T13:23:34+02:00       INFO    azurestackhciProvider: Waiting for Vip Pool
2022-05-05T13:23:34+02:00       INFO    azurestackhciProvider: PersistKubeConfig
2022-05-05T13:23:34+02:00       INFO    core: Waiting for API server...
2022-05-05T13:24:39+02:00       INFO    core: Waiting for pod 'Cloud Operator' to be ready...
2022-05-05T13:27:48+02:00       INFO    core: Waiting for pod 'Cluster API core' to be ready...
2022-05-05T13:29:28+02:00       INFO    core: Waiting for pod 'Bootstrap kubeadm' to be ready...
2022-05-05T13:29:38+02:00       INFO    core: Waiting for pod 'Control Plane kubeadm' to be ready...
2022-05-05T13:29:59+02:00       INFO    azurestackhciProvider: PerformPostOperations
2022-05-05T13:29:59+02:00       INFO    azurestackhciProvider: Waiting for pod 'AzureStackHCI Provider' to be ready...
2022-05-05T13:30:30+02:00       INFO    core: Waiting for Cluster 'f1a7812c8853538b80690ca95bfb5e880c6c33a2d47ea' to be provisioned...
2022-05-05T13:31:25+02:00       INFO    core: Waiting for Control Plane 'f1a7812c8853538b80690ca95bfb5e880c6c33a2d47ea' to be in running state...
2022-05-05T13:31:26+02:00       INFO    core: Waiting for Arc Agents...
2022-05-05T13:31:26+02:00       INFO    core: Waiting for deployment 'Appliance Connect Agent' to be scheduled...
2022-05-05T13:32:21+02:00       INFO    core: Waiting for deployment 'Cluster Connect Agent' to be ready...
2022-05-05T13:39:40+02:00       INFO    core: Waiting for deployment 'Config Agent' to be scheduled...
2022-05-05T13:39:40+02:00       INFO    core: Waiting for deployment 'Extension Manager' to be ready...
2022-05-05T13:39:40+02:00       INFO    core: Waiting for secret 'appliance-public-key' to be created...
2022-05-05T13:39:41+02:00       INFO    Setting appliance status to Phase: 'Deployed', Details: '', LastError: ''
Appliance creation was successful

#>
#endregion

#region Snippet 11: Create arc bridge
    az arcappliance create hci --config-file "$ARBPath\hci-appliance.yaml" --kubeconfig "$env:USERPROFILE\.kube\config"
    #---->wait a while - go to the azure portal and check the status of the resource bridge waitingforheartbeat, validating, connecting, connected, Running

<#
PS C:\Users\Administrator.CONTOSO> az arcappliance create hci --config-file "$ARBPath\hci-appliance.yaml" --kubeconfig "$env:USERPROFILE\.kube\config"
Command group 'arcappliance create' is in preview and under development. Reference and support levels: https://aka.ms/CLI_refstatus
{
  "distro": "AKSEdge",
  "id": "/subscriptions/fa6d5c70-.........66b9038c44eb/resourcegroups/rg-onpremvm/providers/microsoft.resourceconnector/appliances/bfazstackhci-arcbridge",
  "identity": {
    "principalId": "3749bc8c-d............924a",
    "tenantId": "bcc71c32-1770.................",
    "type": "SystemAssigned"
  },
  "infrastructureConfig": {
    "provider": "HCI"
  },
  "location": "westeurope",
  "name": "bfazstackhci-arcbridge",
  "provisioningState": "Succeeded",
  "publicKey": "MIICCgKCAgEAx3hwjWapTnl2sE95ASchjXRGAncZv+BIy+QAKN6p16Mvj6NHqrIOjdBc.......................5nBeXWJbIDD0/9u3VeDiFcrOTe7tBo95BDXZu09hfk1t6QzYkhbFdXtOMMJanBvZd62RoEjtWQF7aV3msLQ369k6eO4xwtsaPFN4vTUXp5TYCwVNoQ3H9YDU5xOdtqOun/cqe6PMk7JfyAwmxdG7t3tRWOiaZJcUfM/PKntnpsGTlh8s/17RoI9ZGK5yJHhscz/Pgwbm85P8JnKM+SMcDoEQKvslcSRygSsPGVv88mEPzOQN9A3Em+M7Vm+rhn/GtsLWzNBgqmzDGxjRtGwjVCzGdt+JG5gZ7DiQpvbbHudutdgIRmkhrGlPOm4Xe5PhqV5B5e60e6jfFGLLg2OAN837rgoAj91yifPq4kzXng/OmgzjJoXqED8POaqYlg0kDpIeC89TMfmfi2gDLnjx8idYKXhwDpycBteQ1HlXTnGk5U0fwdyg6LPfdI1akVG+NsYg9CvZAQ3DZfrHM0w96/2G+9XazLurWcS+iu0U+SeTlH+/8dHd8/4yq9wV6znNYFj0t8WAtghYbLDvEDPF/JrakBjv4MVf1Pf8BME0yq3lJyZc6hiRysCAwEAAQ==",
  "resourceGroup": "rg-onpremvm",
  "status": "Validating",
  "systemData": {
    "createdAt": "2022-05-05T11:46:48.624710+00:00",
    "createdBy": "admin@..........onmicrosoft.com",
    "createdByType": "User",
    "lastModifiedAt": "2022-05-05T11:46:48.624710+00:00",
    "lastModifiedBy": "admin@..........onmicrosoft.com",
    "lastModifiedByType": "User"
  },
  "tags": null,
  "type": "Microsoft.ResourceConnector/appliances",
  "version": null
}

#>
#endregion

#region Snippet 12: Wait until ARB is running
    az arcappliance show --resource-group $resource_group --name $resource_name

    <#
Command group 'arcappliance' is in preview and under development. Reference and support levels: https://aka.ms/CLI_refstatus
{
  "distro": "AKSEdge",
  "id": "/subscriptions/fa6d5c70-.........66b9038c44eb/resourcegroups/rg-onpremvm/providers/microsoft.resourceconnector/appliances/bfazstackhci-arcbridge",
  "identity": {
    "principalId": "3749bc8c-d............924a",
    "tenantId": "bcc71c32-1770.................",
    "type": "SystemAssigned"
  },
  "infrastructureConfig": {
    "provider": "HCI"
  },
  "location": "westeurope",
  "name": "bfazstackhci-arcbridge",
  "provisioningState": "Succeeded",
  "publicKey": "MIICCgKCAgEAx3hwjWapTnl2.........................VsuXC050C6DNqqj5nBeXWJbIDD0/9u3VeDiFcrOTe7tBo95BDXZu09hfk1t6QzYkhbFdXtOMMJanBvZd62RoEjtWQF7aV3msLQ369k6eO4xwtsaPFN4vTUXp5TYCwVNoQ3H9YDU5xOdtqOun/cqe6PMk7JfyAwmxdG7t3tRWOiaZJcUfM/PKntnpsGTlh8s/17RoI9ZGK5yJHhscz/Pgwbm85P8JnKM+SMcDoEQKvslcSRygSsPGVv88mEPzOQN9A3Em+M7Vm+rhn/GtsLWzNBgqmzDGxjRtGwjVCzGdt+JG5gZ7DiQpvbbHudutdgIRmkhrGlPOm4Xe5PhqV5B5e60e6jfFGLLg2OAN837rgoAj91yifPq4kzXng/OmgzjJoXqED8POaqYlg0kDpIeC89TMfmfi2gDLnjx8idYKXhwDpycBteQ1HlXTnGk5U0fwdyg6LPfdI1akVG+NsYg9CvZAQ3DZfrHM0w96/2G+9XazLurWcS+iu0U+SeTlH+/8dHd8/4yq9wV6znNYFj0t8WAtghYbLDvEDPF/JrakBjv4MVf1Pf8BME0yq3lJyZc6hiRysCAwEAAQ==",
  "resourceGroup": "rg-onpremvm",
  "status": "Running",

#>
#endregion

#region Snippet 13: Get hci-vmoperator extension imported

# 5mins - Add the required extensions for VM management capabilities to be enabled via the newly deployed Arc Resource Bridge:
$hciClusterId = (Get-AzureStackHci).AzureResourceUri
#$resource_name = ((Get-AzureStackHci).AzureResourceName) + "-arcbridge"
az k8s-extension create --cluster-type appliances --cluster-name $resource_name --resource-group $resource_group --name hci-vmoperator --extension-type Microsoft.AZStackHCI.Operator --scope cluster --release-namespace helm-operator2 --configuration-settings Microsoft.CustomLocation.ServiceAccount=hci-vmoperator --configuration-protected-settings-file "$ARBPath\hci-config.json" --configuration-settings HCIClusterID=$hciClusterId --auto-upgrade true

# if things go wrong you could try
#az k8s-extension create --cluster-type appliances --cluster-name $resource_name --resource-group $resource_group --name hci-vmoperator --extension-type Microsoft.AZStackHCI.Operator --scope cluster --release-namespace helm-operator2 --configuration-settings Microsoft.CustomLocation.ServiceAccount=hci-vmoperator --configuration-protected-settings-file "$ARBPath\hci-config.json" --configuration-settings HCIClusterID=$hciClusterId --version 1.2.7   # 1.2.6, 1.2.5

<#
{
  "aksAssignedIdentity": null,
  "autoUpgradeMinorVersion": true,
  "configurationProtectedSettings": {
    "secret.cloudFQDN": "",
    "secret.loginString": ""
  },
  "configurationSettings": {
    "HCIClusterID": "/Subscriptions/fa6d5c70-.........66b9038c44eb/resourceGroups/rg-AzStackHCI-R720/providers/Microsoft.AzureStackHCI/clusters/bfAzStackHCI",
    "Microsoft.CustomLocation.ServiceAccount": "hci-vmoperator"
  },
  "customLocationSettings": null,
  "errorInfo": null,
  "extensionType": "microsoft.azstackhci.operator",
  "id": "/subscriptions/fa6d5c70-.........66b9038c44eb/resourceGroups/rg-onpremvm/providers/Microsoft.ResourceConnector/appliances/bfAzStackHCI-arcbridge/providers/Microsoft.KubernetesConfiguration/extensions/hci-vmoperator",
  "identity": null,
  "name": "hci-vmoperator",
  "packageUri": null,
  "provisioningState": "Succeeded",
  "releaseTrain": "Stable",
#>

<# 
(ExtensionCreationFailed)  Error: {failed to setup Helm client failed to do request: Head "https://hybridaks.azurecr.io/v2/azstackhci-chart/manifests/1.2.3": dial tcp 52.168.114.2:443: i/o timeout} occurred while doing the operation : {Installing the extension} on the config
Code: ExtensionCreationFailed
Message:  Error: {failed to setup Helm client failed to do request: Head "https://hybridaks.azurecr.io/v2/azstackhci-chart/manifests/1.2.3": dial tcp 52.168.114.2:443: i/o timeout} occurred while doing the operation : {Installing the extension} on the config
->rerun

1st error:
(ExtensionCreationFailed)  error: Unable to get the status from the local CRD with the error : { Get-Error : Retry for given duration didn't get any results with err {status not populated}}
Code: ExtensionCreationFailed...
-> rerun.

2nd error.
-> rerun
-> success....
#>

    # Verify that the extensions are installed
    az k8s-extension show --cluster-type appliances --cluster-name $resource_name --resource-group $resource_group --name hci-vmoperator

#endregion 

#region Snippet 14: Create a custom location
az customlocation create --resource-group $resource_group --name $customloc_name --cluster-extension-ids "/subscriptions/$SubscriptionId/resourceGroups/$resource_group/providers/Microsoft.ResourceConnector/appliances/$resource_name/providers/Microsoft.KubernetesConfiguration/extensions/hci-vmoperator" --namespace hci-vmoperator --host-resource-id "/subscriptions/$SubscriptionId/resourceGroups/$resource_group/providers/Microsoft.ResourceConnector/appliances/$resource_name" --location $Location

<#
{
  "authentication": {
    "type": null,
    "value": null
  },
  "clusterExtensionIds": [
    "/subscriptions/fa6d5c70-.........66b9038c44eb/resourceGroups/rg-onpremvm/providers/Microsoft.ResourceConnector/appliances/bfAzStackHCI-arcbridge/providers/Microsoft.KubernetesConfiguration/extensions/hci-vmoperator"
  ],
  "displayName": "Regensburg",
  "hostResourceId": "/subscriptions/fa6d5c70-.........66b9038c44eb/resourceGroups/rg-onpremvm/providers/Microsoft.ResourceConnector/appliances/bfAzStackHCI-arcbridge",
  "hostType": "Kubernetes",
  "id": "/subscriptions/fa6d5c70-.........66b9038c44eb/resourcegroups/rg-onpremvm/providers/microsoft.extendedlocation/customlocations/regensburg",
    "identity": null,
  "location": "westeurope",
  "name": "regensburg",
  "namespace": "hci-vmoperator",
  "provisioningState": "Succeeded",
#>
#endregion

#region Snippet 15: Deploy Azure Resouce Bridge Network (requirement)

# deploy network
#$vswitchName = "ComputeSwitch"
#$vswitchName = Get-Option "Get-VMSwitch" "Name"
az azurestackhci virtualnetwork create --subscription $SubscriptionId --resource-group $resource_group --extended-location name="/subscriptions/$SubscriptionId/resourceGroups/$resource_group/providers/Microsoft.ExtendedLocation/customLocations/$customloc_name" type="CustomLocation" --location $Location --network-type "Transparent" --name $vswitchName

<#
{
  "extendedLocation": {
    "name": "/subscriptions/fa6d5c70-.........66b9038c44eb/resourceGroups/rg-onpremvm/providers/Microsoft.ExtendedLocation/customLocations/Regensburg",
    "type": "CustomLocation"
  },
  "id": "/subscriptions/fa6d5c70-.........66b9038c44eb/resourceGroups/rg-onpremvm/providers/Microsoft.AzureStackHCI/virtualnetworks/ComputeSwitch",
  "location": "westeurope",
  "name": "ComputeSwitch",
  "properties": {
    "networkType": "Transparent",
    "provisioningState": "Succeeded",
#>

    #region arc bridge network with vlan or special characters (e.g. when created with network intent)
      $tags = @{
    'VSwitch-Name' = "ComputeSwitch" #hyper-v switch name
  }
      $customLocationNetworkName = "VM network 1" #this is what the customer sees in the portal
      New-MocVirtualNetwork -Name $customLocationNetworkName -group "Default_Group" -tags $tags -vlanID 123 #-ippools $IPPool
      az azurestackhci virtualnetwork create --subscription $SubscriptionId --resource-group $resource_group --extended-location name="/subscriptions/$SubscriptionId/resourceGroups/$resource_group/providers/Microsoft.ExtendedLocation/customLocations/$customloc_name" type="CustomLocation" --location $Location --network-type "Transparent" --name $customLocationNetworkName
    #endregion

#endregion

#region Snippet 16: Deploy Azure Resouce Bridge vm image (requirement)
    
    #Important!!!!! Do just this line on the Host e.g. AzSHCIHost001


    #Now !!! go back to your azshost1
    # VM Image for Arc Bridge
    $galleryImageName = "custom-win2k22-server"
    $galleryImageSourcePath = "$csv_path\ArcBridgeImages\W2k22.vhdx"
    $osType = "Windows"

        if (!(Test-Path $galleryImageSourcePath))
    {
        "You don't have an vhdx or your galleryImageSourcePath is incorrect."
    }

    #create image
    #.\Convert-WindowsImage.ps1 -SourcePath "$csv_path\17763.1.180914-1434.rs5_release_SERVER_EVAL_x64FRE_en-us.iso" -VHDPath "$csv_path\Images\W2k19.vhdx" -VHDFormat VHDX -DiskLayout UEFI -Edition 4 -RemoteDesktopEnable -Verbose
    # .\CreateWindowVhdxFromIso.ps1 -SourcePath "D:\ISO\14393.0.161119-1705.RS1_REFRESH_SERVER_EVAL_X64FRE_EN-US.ISO" -VHDPath D:\VMs\images\Disk.vhdx -SizeBytes 96GB -VHDFormat VHDX -DiskLayout UEFI -ImageIndex 4 -RemoteDesktopEnable 
    az azurestackhci galleryimage create --subscription $SubscriptionId --resource-group $resource_group --extended-location name="/subscriptions/$SubscriptionId/resourceGroups/$resource_group/providers/Microsoft.ExtendedLocation/customLocations/$customloc_name" type="CustomLocation" --location $Location --image-path $galleryImageSourcePath --name $galleryImageName --os-type $osType
    
    <#
{
  "extendedLocation": {
    "name": "/subscriptions/fa6d5c70-.........66b9038c44eb/resourceGroups/rg-nestedHCI/providers/Microsoft.ExtendedLocation/customLocations/myNestedHCILocation",
    "type": "CustomLocation"
  },
  "id": "/subscriptions/fa6d5c70-.........66b9038c44eb/resourceGroups/rg-nestedHCI/providers/Microsoft.AzureStackHCI/galleryimages/custom-win2k22-server",
  "location": "westeurope",
  "name": "custom-win2k22-server",
  "properties": {
    "containerName": null,
    "imagePath": null,
    "osType": "Windows",
    "provisioningState": "Succeeded",
    "status": null
  },
  "resourceGroup": "rg-nestedHCI",
  "systemData": {
    "createdAt": "2022-09-06T14:31:05.379727+00:00",
  .
  .
  .
  },
  "tags": null,
  "type": "microsoft.azurestackhci/galleryimages"
}

#>
#endregion


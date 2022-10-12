<# 

  This script should uninstall ARB and AKS
  
  Warning: don't run from top to bottom all at once....
  run in snippets. 
  before you execute code - change names, paths (e.g. CSV location), and most important adopt to your IP address ranges 

    References:
    https://learn.microsoft.com/en-us/azure-stack/hci/manage/uninstall-arc-resource-bridge?source=recommendations
  #>


#region Snippet 0: Get-Option helper function to provide menu
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

#region uninstall ARB

az login --use-device-code

$token = az account get-access-token | ConvertFrom-Json
$ctx = az account show | ConvertFrom-Json


#$VerbosePreference = "Continue"
Connect-AzAccount -AccessToken $token.accessToken -AccountId $ctx.user.name

$sub = Get-Option "Get-AzSubscription" "Name" # alternatively you can choose "SubscriptionID" if you a
Set-AzContext $sub


$csv_path = "c:\clusterstorage\CSV1"
$ARBPath = "$csv_path\ResourceBridge"
$customloc_name = "HCIonprem"  #You may want to change this.

$resource_name = ((Get-AzureStackHci).AzureResourceName) + "-arcbridge"
$subctx = $sub

"select the resource group that contains the ARB custom location (network, images)"
$resource_group = Get-Option "Get-AzResourceGroup" "ResourceGroupName"

$vnetName = Get-Option "Get-vmswitch" "Name"
az azurestackhci virtualnetwork delete --subscription $($subctx.Subscription.SubscriptionId) --resource-group $resource_group --name $vnetName --yes

$galleryImageName = Get-Option "Get-azresource -resourcetype 'Microsoft.AzureStackHCI/galleryimages'" "Name"
az azurestackhci galleryimage delete --subscription $($subctx.Subscription.SubscriptionId) --resource-group $resource_group --name $galleryImageName
az customlocation delete --resource-group $resource_group --name $customloc_name --yes
az k8s-extension delete --cluster-type appliances --cluster-name $resource_name --resource-group $resource_group --name hci-vmoperator --yes
az arcappliance delete hci --config-file $ARBPath\hci-appliance.yaml --yes

#Remove the config files:
Remove-ArcHciConfigFiles

#remove arc bridge
# need to have the ca and vms running.

az extension remove --name arcappliance
az extension remove --name connectedk8s
az extension remove --name k8s-configuration
az extension remove --name k8s-extension
az extension remove --name customlocation
az extension remove --name azurestackhci

Uninstall-Module -Name "ArcHci" -Verbose
#endregion 

#region uninstall AKS
  Uninstall-akshci -Verbose -Debug
  Uninstall-Moc -Verbose  #will remove CAgent.
  Uninstall-Module -Name "AksHci" -Verbose
  Uninstall-Module -Name "Moc" -Verbose
#endregion

Install-Module -Name ArcHci -Force -Confirm:$false -SkipPublisherCheck -AcceptLicense

#clear CSV directory on C:\ClusterStorage\ResourceBridge and others. 

#Install-Module -Name AzureAD -Repository PSGallery -Force 
#Install-Module -Name AksHci -Repository PSGallery -Force -AcceptLicense
#Install-Module -Name Moc -Repository PSGallery -Force -AcceptLicense
#Install-Module -Name ArcHci -Repository PSGallery -Force -Confirm:$false -SkipPublisherCheck -AcceptLicense

#Update-Module AzureAD
#Update-Module -Name AksHci 
#Update-Module -Name Moc
#Update-Module -Name ArcHci

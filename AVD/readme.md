# How To Deploy AVD On AzStack HCI

## Manually
See: [Set up Azure Virtual Desktop for Azure Stack HCI (preview) - manual](https://learn.microsoft.com/en-us/azure/virtual-desktop/azure-stack-hci?tabs=manual-setup)

0. You require: A registered HCI cluster, AD sync'ed with AAD, a valid Azure subscription
1. Download the VDI image from the Azure marketplace you want to use.
2. (optional) Optimize image e.g. convert to dynamically expanding vhdx to save disk space.
3. (optional - but likely) Create a VM for golden image creation: E.g. to run windows update, install your language packs, applications, frameworks, runtimes -> sysprep (!!!important!!! using: mode:vm) -> Checkpoint for later re-use.
   > Note: Only install what will 'survive' a sysprep (e.g. don't do ARC Agent nor AVD Hostpool registration yet) 
4. (optional) FSLogix: Prepare a SMB file share (provide profile share with correct ACLs)
5. (optional) FSLogix: Prepare a GPO for the AD OrgUnit (OU) the VDIs will be joined to.
6. Deploy a empty AVD Hostpool in Azure.
7. Create a Application Group for this Hostpool and allow an AAD User Group access to it.
8. Create a Workspace containing the App Group created before.
9. Deploy a VDI VM on HCI using the VDI image (from vhdx obtained in 1./2. or 3.)
10. Deploy the AVD Agents into the VDI VM
11. Deploy the Remote Desktop App for the User
12. (When using Win 10|11 multisession) - [Enable Azure Benefits](https://learn.microsoft.com/en-us/azure-stack/hci/manage/azure-benefits)
13. (optional) when you are using proxies for the session hosts.

## 1. Download the VDI image from the Azure marketplace you want to use
Do this on an admin box 
```Powershell
#Make sure you have the Azure modules required

$modules = @("Az.Accounts","Az.Resources","Az.Compute")
    
foreach ($module in $modules) {
    if (!(Get-Module -Name $module -ListAvailable)) {
        Install-Module -Name $module -Force -Verbose
    }
}

#login to Azure
Login-AzAccount -Environment AzureCloud #-Tenant blabla.onmicrosoft.com  -UseDeviceAuthentication
   
#hit the right subscription
Get-AzSubscription | Out-GridView -Title "Select the right subscription" -OutputMode Single | Select-AzSubscription

#we need the context info later
$azureContext = Get-AzContext 

#select a location near you
$location = Get-AzLocation | Out-GridView -Title "Select your location (e.g. westeurope)" -OutputMode Single

#region select an Azure AVD Image (e.g. Windows 11) and create an Azure disk of it for later download (to onprem)
    #get the AVDs group published images by selecting 'microsoftwindowsdesktop'
    $imPub = Get-AzVMImagePublisher -Location $($location.Location) | Out-GridView -Title "Select image publisher (e.g. 'microsoftwindowsdesktop')" -OutputMode Single

    #select the AVD Desktop OS of interest e.g. 'windows-11'
    $PublisherOffer = Get-AzVMImageOffer -Location $($location.Location) -PublisherName $($imPub.PublisherName) |  Out-GridView -Title "Select your offer (e.g. windows-11)" -OutputMode Single

    # select the AVD version e.g. 'win11-21h2-avd'
    $VMImageSKU = (Get-AzVMImageSku -Location $($location.Location) -PublisherName $($imPub.PublisherName) -Offer $PublisherOffer.Offer).Skus | Out-GridView -Title "Select your imagesku (e.g. win11-22h2-avd)" -OutputMode Single

    #select latest version
    $VMImage = Get-AzVMImage -Location $($location.Location) -PublisherName $PublisherOffer.PublisherName -Offer $PublisherOffer.Offer -Skus $VMImageSKU | Out-GridView -Title "Select your version (highest build number)" -OutputMode Single

    #Create a VHDX (Gen2) from this image
    $imageOSDiskRef = @{Id = $vmImage.Id}
    $diskRG = Get-AzResourceGroup | Out-GridView -Title "Select The Target Resource Group" -OutputMode Single
    $diskName = "disk-" + $vmImage.Skus
    $newdisk = New-AzDisk -ResourceGroupName $diskRG.ResourceGroupName -DiskName "$diskName" -Disk $(New-AzDiskConfig -ImageReference $imageOSDiskRef -Location $location.Location -CreateOption FromImage -HyperVGeneration V2 -OsType Windows )

    Write-Host "You should now have a new disk named $($newdisk.name) in your resourcegroup" -ForegroundColor Green  
#endregion
```
Next is to download the Azure disk to one of your HCI nodes:  
```PowerShell
#region Create a temp. download link and download the disk as virtual disk (.vhd)
    $AccessSAS =  $newdisk | Grant-AzDiskAccess -DurationInSecond ([System.TimeSpan]::Parse("05:00:00").TotalSeconds) -Access 'Read'
    Write-Host "Generating a temporary download access token for $($newdisk.Name)" -ForegroundColor Green 
    $DiskURI = $AccessSAS.AccessSAS

    $folder = "\\...OneHCINodeHere....\c$\temp"   #enter one of the nodes here - the path must be accessible by the user - beware that there is enough space (127GB) for the disk to be downloaded.

    $diskDestination = "$folder\$($newdisk.Name).vhd"
    Write-Host "Your disk will be placed into: $diskDestination" -ForegroundColor Green
    #"Start-BitsTransfer ""$DiskURI"" ""$diskDestination"" -Priority High -RetryInterval 60 -Verbose -TransferType Download"

    #or use azcopy as it is much faster!!!
    invoke-webrequest -uri "https://aka.ms/downloadazcopy-v10-windows" -OutFile "$env:TEMP\azcopy.zip" -verbose
    Expand-Archive "$env:TEMP\azcopy.zip" "$env:TEMP" -force -verbose
    copy-item "$env:TEMP\azcopy_windows_amd64_*\\azcopy.exe\\" -Destination "$env:TEMP" -verbose
    cd "$env:TEMP\"
    &.\azcopy.exe copy $DiskURI $diskDestination --log-level INFO
    Remove-Item "azcopy*" -Recurse  #cleanup temp
#endregion
```
## 2. (optional) Optimize image e.g. convert to dynamically expanding vhdx to save disk space.

```PowerShell
#region Convert to a dynamic vhdx!
    $finalfolder = "C:\clusterstorage\CSV\Images"        # pls enter an existing final destination to hold the AVD image.
    $diskFinalDestination = "$finalfolder\Win11-multi-opt.vhdx"
    $sourceDiskPath = "c:\temp\disk-win11-22h2-avd.vhd"

    Convert-VHD -Path "$sourceDiskPath" -DestinationPath "$diskFinalDestination" -VHDType Dynamic

    try
    {
        $beforeMount = (Get-Volume).DriveLetter -split ' '
        Mount-VHD -Path $diskFinalDestination
        $afterMount = (Get-Volume).DriveLetter -split ' '
        $driveLetter = $([string](Compare-Object $beforeMount $afterMount -PassThru )).Trim()
        Write-Host "Optimizing disk ($($driveLetter)): $diskFinalDestination" -ForegroundColor Green
        &defrag "$($driveLetter):" /o /u /v
    }
    finally
    {
        Write-Host "dismounting ..."
        Dismount-VHD -Path $diskFinalDestination
    }
      
    Optimize-VHD $diskFinalDestination -Mode full
#endregion
```

## 3. (optional) Create a VM for golden image creation 
You probably want update or use your apps in the VDIs. So you before creating desktops from the image you e.g. might want to ...:
- ...do a windows update run first...
- ...install your language packs...
- ...install SW deployment agents, applications, frameworks, runtimes...
...onto the image - before you finalize it with a sysprep.   

Yes?! -> 
1. Create a VM on HCI using the vhdx file you have just dowloaded|optimized.  
2. Then perform the actions you want as described above.  
3. (optional - recommended) Shutdown the VM in HCI - do a checkpoint - so that you can return to this state later. Boot up again.
4. Then sysprep the vm to get a generalized version you can create VDI clones from.
```
c:\Windows\System32\Sysprep\sysprep.exe /oobe /generalize /shutdown /mode:vm
```
> Important to us the **mode:vm** switch (it'll tell the vm that the virtualization platform (HCI) has not changed)otherwise you might experience long boot times.
5. Export the vm's .vhdx to your HCI cluster's image folder (some place on a CSV)

## 10. Deploy the AVD Agents into the VDI VM
Execute this PS script inside a VDI VM to make it part of a Hostpool. 
>Note: Your VDI VM needs to be domain joined before + must have outbound internet access (it will download stuff and register). You also need to provide a valid %RegistrationToken%

```PowerShell
#region AVD agent download (do this in the VM)
    #https://docs.microsoft.com/en-us/azure/virtual-desktop/create-host-pools-powershell?tabs=azure-powershell#register-the-virtual-machines-to-the-azure-virtual-desktop-host-pool

    #this will be our temp folder - need it for download / logging
    $tmpDir = "c:\temp\" 
    
    #create folder if it doesn't exist
    if (!(Test-Path $tmpDir)) { mkdir $tmpDir -force }
    
    $agentURIs = @{
    'agent.msi' = "https://query.prod.cms.rt.microsoft.com/cms/api/am/binary/RWrmXv"
    'bootloader.msi' = "https://query.prod.cms.rt.microsoft.com/cms/api/am/binary/RWrxrH"}
    
    foreach ($uri in $agentURIs.GetEnumerator())
    {
            Write-Output "starting download...."
            Invoke-WebRequest "$($uri.value)" -OutFile "$tmpDir\$($uri.key)"
    }

    $RegistrationToken = "eyJhbGciOiJ...." # a valid hostpool registration token [Azure portal] -> Azure Virtual Desktop -> Host Pool -> %Your Hostpool%  -> Registration token
    #unattended install
    start-process -filepath msiexec -ArgumentList "/i ""$tmpDir\agent.msi"" /l*v ""$tmpDir\agent.msi.log"" REGISTRATIONTOKEN=$RegistrationToken /passive /qn /quiet /norestart " -Wait
    start-process -filepath msiexec -ArgumentList "/i ""$tmpDir\bootloader.msi"" /l*v ""$tmpDir\bootloader.msi.log""  /quiet /qn /norestart /passive" -Wait

#endregion
```
After some minutes they should show up in the AVD hostpool:  
![VDI VMs (on HCI) in AVD Hostpool](vdivmsinhostpool.png)

## 13. adding proxy...
in order to make the RDagent and RD bootagent use proxies - you may need to run this in the session host:  
```
bitsadmin /util /setieproxy LOCALSYSTEM Manual_Proxy proxy1:8080 null
bitsadmin /util /setieproxy NETWORKSERVICE Manual_Proxy proxy1:8080 null
```
Whereas proxy1:8080 is to be replaced with your proxy and port.

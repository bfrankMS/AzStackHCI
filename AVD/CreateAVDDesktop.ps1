<#
    Attention: Don't run all of this script as at once!!!
    copy and replace the '????????' with your values.
    read the comments to follow where, what the script should be executed + what it does.
    intended to give show the required steps to setup an AVD Desktop onprem on AzStack HCI
#>

#region helper functions (pls run if you want to have a folder picker dialog)
    function ShowFolderOpenDialog ([string]$Title)
    {
        $ui = new-object -ComObject "Shell.Application"
        $path = $ui.BrowseForFolder(0,"$Title",0,0)
        $path.Self.Path
    }
#endregion

#install required Azure PowerShell modules in case the following throws errors.
#Install-Module Az

#login to Azure
Login-AzAccount -Environment AzureCloud #-UseDeviceAuthentication
   
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
    $VMImageSKU = (Get-AzVMImageSku -Location $($location.Location) -PublisherName $($imPub.PublisherName) -Offer $PublisherOffer.Offer).Skus | Out-GridView -Title "Select your imagesku (e.g. win11-21h2-avd)" -OutputMode Single

    #select latest version
    $VMImage = Get-AzVMImage -Location $($location.Location) -PublisherName $PublisherOffer.PublisherName -Offer $PublisherOffer.Offer -Skus $VMImageSKU | Out-GridView -Title "Select your version" -OutputMode Single

    #Create a VHDX (Gen2) from this image
    $imageOSDiskRef = @{Id = $vmImage.Id}
    $diskRG = Get-AzResourceGroup | Out-GridView -Title "Select The Target Resource Group" -OutputMode Single
    $diskName = "disk-" + $vmImage.Skus
    $newdisk = New-AzDisk -ResourceGroupName $diskRG.ResourceGroupName -DiskName "$diskName" -Disk $(New-AzDiskConfig -ImageReference $imageOSDiskRef -Location $location.Location -CreateOption FromImage -HyperVGeneration V2 -OsType Windows)

    Write-Host "You should now have a new disk named $(newdisk.name) in your resourcegroup" -ForegroundColor Green
#endregion

#region Create a temp. download link and download the disk as virtual disk (.vhd)
    $AccessSAS =  $newdisk | Grant-AzDiskAccess -DurationInSecond ([System.TimeSpan]::Parse("05:00:00").TotalSeconds) -Access 'Read'
    $newdisk.Name
    $DiskURI = $AccessSAS.AccessSAS

    $folder = ShowFolderOpenDialog "Where should your disk goto?"
    $diskDestination = "$folder\$($newdisk.Name).vhd"
    Write-Host "Your disk will be placed into: $diskDestination" -ForegroundColor Green
    #"Start-BitsTransfer ""$DiskURI"" ""$diskDestination"" -Priority High -RetryInterval 60 -Verbose -TransferType Download"

    #or use azcopy as it is much faster!!!
    invoke-webrequest -uri "https://aka.ms/downloadazcopy-v10-windows" -OutFile "$folder\azcopy.zip" -verbose
    Expand-Archive "$folder\azcopy.zip" "$folder" -force -verbose
    copy-item "$folder\azcopy_windows_amd64_*\\azcopy.exe\\" -Destination "$folder" -verbose
    cd "$folder\"
    .\azcopy.exe copy $DiskURI $diskDestination
#endregion

#region Convert to a dynamic vhdx!
    $finalfolder = ShowFolderOpenDialog "Where should your compressed dynamic vhdx disk go?"
    $diskFinalDestination = "$finalfolder\$($newdisk.Name).vhdx"
    Convert-VHD -Path "$diskDestination" -DestinationPath "$diskFinalDestination" -VHDType Dynamic
#endregion

# Do copy the disk to your AzStack HCI cluster storage
# Do create a new VM (Gen2) based on this new disk.
# Do a Enter-PSSession to your AzStack HCI node e.g by 
etsn azhci1node1   # '????????' requires your node name here
sleep 3

#region Do domain join of VM - manual! or using a script e.g. below
    #which VM?
    do {
        $vms = @("")
       Get-VM | foreach -Begin { $i = 0 } -Process {
            $i++
            $vms += "{0}. {1}" -f $i, $_.Name
        } -outvariable menu
        $vms | Format-Wide { $_ } -Column 4 -Force
        $r = Read-Host "Select a vm"
        $vm = $vms[$r].Split()[1]
        if ($vm -eq $null) { Write-Host "You must make a valid selection" -ForegroundColor Red }
        else {
            Write-Host "Selecting vm $($vms[$r])" -ForegroundColor Green
        }
    }
    until ($vm -ne $null)
    
    #enter powershell session into VM
    etsn -VMName $vm
    
    #make IP Addresses & DNS settings
    $InterfaceAlias =  (Get-NetAdapter | Get-NetIPAddress | where Addressfamily -eq "IPv4").InterfaceAlias
    Set-DnsClientServerAddress -InterfaceAlias "$InterfaceAlias" -ServerAddresses "192.168.xxx.xxx" #'????????'
    
    New-NetIPAddress -InterfaceAlias $InterfaceAlias -IPAddress 192.168.xxx.xxx -PrefixLength 24 -DefaultGateway 192.168.xxx.xxx -AddressFamily IPv4
    $newVMName = "W11-0815" #   '????????'
    $DomainName = "contoso" #   '????????'
    $credential = get-credential -Message "domain creds" -UserName "$DomainName\administrator"
    Add-Computer -ComputerName localhost -NewName $newVMName -DomainName $DomainName -Credential $credential -Verbose -Restart #-OUPath "OU=Hostpool1,OU=AVD,DC=contoso,DC=local"
#endregion


#vm has restarted? Tunnel into it again!
Enter-PSSession -VMName $vm

#region Do Arc onboarding - !!!Must fill in the ???????? values before!!!
    # Download the installation package
    Invoke-WebRequest -Uri "https://aka.ms/azcmagent-windows" -TimeoutSec 30 -OutFile "$env:TEMP\install_windows_azcmagent.ps1"

        # Install the hybrid agent
    & "$env:TEMP\install_windows_azcmagent.ps1"
    if($LASTEXITCODE -ne 0) {
        throw "Failed to install the hybrid agent"
    }
    # Run connect command
    & "$env:ProgramW6432\AzureConnectedMachineAgent\azcmagent.exe" connect `
        --resource-group "RG-????????" `
        --tenant-id "16a6152e-????????" `
        --location "westeurope" `
        --subscription-id "ad8d0fcf-????????" `
        --cloud "AzureCloud" `
        --tags "Datacenter=RZ1,City=SomeCity,CountryOrRegion=Germany"
    
    if($LastExitCode -eq 0){Write-Host -ForegroundColor yellow "To view your onboarded server(s), navigate to https://portal.azure.com/#blade/HubsExtension/BrowseResource/resourceType/Microsoft.HybridCompute%2Fmachines"}
#endregion

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
#endregion

# Log on to the VM
# Do Install the c:\temp\agent.msi
# Do copy & paste the Azure -> Azure Virtual Desktop -> Hostpool -> Registration Token -> into the Agent install window
# Do Install the C:\temp\bootloader.msi
# Now your VM should show up in Azure -> Azure Virtual Desktop -> Hostpool -> Session Host


#region RDP Shortpath FW rule in Desktop (part1)
    # https://docs.microsoft.com/en-us/azure/virtual-desktop/shortpath
    New-NetFirewallRule -DisplayName 'Remote Desktop - Shortpath (UDP-In)'  -Action Allow -Description 'Inbound rule for the Remote Desktop service to allow RDP traffic. [UDP 3390]' -Group '@FirewallAPI.dll,-28752' -Name 'RemoteDesktop-UserMode-In-Shortpath-UDP'  -PolicyStore PersistentStore -Profile Domain, Private -Service TermService -Protocol udp -LocalPort 3390 -Program '%SystemRoot%\system32\svchost.exe' -Enabled:True

    # you then need to do add the GPO to your AD see:
    # https://docs.microsoft.com/en-us/azure/virtual-desktop/shortpath#configure-rdp-shortpath-for-managed-networks
#endregion 
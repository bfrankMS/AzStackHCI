$OUSuffix = "OU=AVDHosts,OU=HCI"  #the part after the "...,DC=powerkurs,DC=local" so e.g. "OU=HostPool1,OU=AVD"


#this will be our temp folder - need it for download / logging
$tmpDir = "c:\temp\" 

#create folder if it doesn't exist
if (!(Test-Path $tmpDir)) { mkdir $tmpDir -force }

#downloading FSLogix.
Write-Output "downloading fslogix"

$tempPath = "$tmpDir\FSLogix"
$destinationPath = "$tmpDir\FSLogix.zip"
if (!(Test-Path $destinationPath)) {
    "downloading fslogix"
    Invoke-WebRequest -Uri "https://aka.ms/fslogix_download" -OutFile $destinationPath -verbose
    Expand-Archive $destinationPath -DestinationPath $tempPath -Force -verbose
}

$fqdn = (Get-WmiObject Win32_ComputerSystem).Domain
$policyDestination = "Microsoft.PowerShell.Core\FileSystem::\\$fqdn\SYSVOL\$fqdn\policies\PolicyDefinitions\"

mkdir $policyDestination -Force
mkdir "$policyDestination\en-us" -Force
Copy-Item "Microsoft.PowerShell.Core\FileSystem::$tempPath\*" -filter "*.admx" -Destination "Microsoft.PowerShell.Core\FileSystem::\\$fqdn\SYSVOL\$fqdn\policies\PolicyDefinitions" -Force -Verbose
Copy-Item "Microsoft.PowerShell.Core\FileSystem::$tempPath\*" -filter "*.adml" -Destination "Microsoft.PowerShell.Core\FileSystem::\\$fqdn\SYSVOL\$fqdn\policies\PolicyDefinitions\en-us" -Force -Verbose


$gpoName = "FSLogixDefExcl{0}" -f [datetime]::Now.ToString('dd-MM-yy_HHmmss') 
New-GPO -Name $gpoName 
$FSLogixRegKeys = @{
    Enabled = 
    @{
        Type  = "DWord"
        Value = 1           #set to 1 to enable.
    }
    VHDLocations = 
    @{
        Type  = "String"
        Value = "\\SOFS\Profile1;\\SOFS\Profile2"
    }
    DeleteLocalProfileWhenVHDShouldApply =
    @{
        Type  = "DWord"
        Value = 1
    }
    VolumeType = 
    @{
        Type  = "String"
        Value = "VHDX"
    }
    SizeInMBs = 
    @{
        Type  = "DWord"
        Value = 30000
    }
    IsDynamic = 
    @{
        Type  = "DWord"
        Value = 1
    }
    PreventLoginWithFailure = 
    @{
        Type  = "DWord"
        Value = 0
    }
    LockedRetryInterval = 
    @{
        Type  = "DWord"
        Value = 10
    }
    LockedRetryCount = 
    @{
        Type  = "DWord"
        Value = 5
    }
    FlipFlopProfileDirectoryName = 
    @{
        Type = "DWord"
        Value = 1
    }
}

foreach ($item in $FSLogixRegKeys.GetEnumerator()) {
    "{0}:{1}:{2}" -f $item.Name, $item.Value.Type, $item.Value.Value
    Set-GPRegistryValue -Name $gpoName -Key "HKEY_LOCAL_MACHINE\SOFTWARE\fslogix\profiles" -ValueName $($item.Name) -Value $($item.Value.Value) -Type $($item.Value.Type)
}

#enable path exclusions in windows defender for fslogix profiles
Set-GPRegistryValue -Name $gpoName -Key "HKEY_LOCAL_MACHINE\Software\Policies\Microsoft\Windows Defender\Exclusions" -ValueName "Exclusions_Paths" -Value 1 -Type DWord

$excludeList = @"
%ProgramFiles%\FSLogix\Apps\frxdrv.sys,
%ProgramFiles%\FSLogix\Apps\frxdrvvt.sys,
%ProgramFiles%\FSLogix\Apps\frxccd.sys,
%TEMP%\*.VHD,
%TEMP%\*.VHDX,
%Windir%\TEMP\*.VHD,
%Windir%\TEMP\*.VHDX,
\\SOFS\Profile1\*\*.VHD,
\\SOFS\Profile1\*\*.VHDX,
\\SOFS\Profile2\*\*.VHD,
\\SOFS\Profile2\*\*.VHDX
"@
foreach ($item in $($excludeList -split ',')) {
    $item.Trim()
    Set-GPRegistryValue -Name $gpoName -Key "HKEY_LOCAL_MACHINE\Software\Policies\Microsoft\Windows Defender\Exclusions\Paths"  -ValueName "$($item.Trim())" -Value 0 -Type String 
}

Import-Module ActiveDirectory
$DomainPath = $((Get-ADDomain).DistinguishedName) # e.g."DC=contoso,DC=azure"

$OUPath = $($($OUSuffix + "," + $DomainPath).Split(',').trim() | where { $_ -ne "" }) -join ','
Write-Output "creating FSLOGIX GPO to OU: $OUPath"

$existingGPOs = (Get-GPInheritance -Target $OUPath).GpoLinks | Where-Object DisplayName -Like "FSLogixDefExcl*"

if ($existingGPOs -ne $null) {
    Write-Output "removing conflicting GPOs"
    $existingGPOs | Remove-GPLink -Verbose
}


New-GPLink -Name $gpoName -Target $OUPath -LinkEnabled Yes -verbose

#cleanup existing but unlinked fslogix GPOs
$existingGPOs | % { [xml]$Report = Get-GPO -guid $_.GpoId | Get-GPOReport -ReportType XML; if (!($Report.GPO.LinksTo)) { Remove-GPO -Guid $_.GpoId -Verbose } }


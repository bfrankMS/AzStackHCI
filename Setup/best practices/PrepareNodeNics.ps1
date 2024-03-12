# Renames Network Adapters, disables IPv6 and disables unused adapters
# Do this on every node.

install-module psmenu   #will provide you with a menu to chose

$nicNames =@("COMP1","COMP2","SMB1","SMB2")     #replace with your names should be the same on all nodes

foreach ($nicName in $nicNames)
{
    Write-Host -ForegroundColor Cyan "Which adapter should be renamed to >> $nicName << ?"
    $selectedNic = $null
    $selectedNic = show-Menu -MenuItems $(get-netadapter | sort-object MacAddress) -MenuItemFormatter { "{0}`t{1}`t{2}`t{3}" -f $args.MacAddress, $args.Name, $args.InterfaceDescription, $args.LinkSpeed}
    if ($null -ne $selectedNic)
    {
        Rename-NetAdapter -InputObject $selectedNic -NewName $nicName
    }
    ""
}

Write-Host -ForegroundColor Cyan "Which adapters should get unique names ?"
$selectedNics = show-Menu -MenuItems $(get-netadapter | sort-object MacAddress) -MenuItemFormatter { "{0}`t{1}`t{2}" -f $args.MacAddress, $args.Name, $args.InterfaceDescription} -multiselect

foreach ($nic in $selectedNics)
{
    Rename-NetAdapter -InputObject $nic -NewName $("$($nic.Name)" + "_" + $env:COMPUTERNAME)
}

Write-Host -ForegroundColor Cyan "Which adapters should not be used (will be disabled) ?"
$toDisableNics = show-Menu -MenuItems $(get-netadapter | sort-object MacAddress) -MenuItemFormatter { "{0}`t{1}`t{2}" -f $args.MacAddress, $args.Name, $args.InterfaceDescription} -multiselect

foreach ($nic in $toDisableNics)
{
    Disable-NetAdapter -InputObject $nic -Verbose
}
Write-Host -ForegroundColor Cyan "Disabling IPv6 on all adapters."
Disable-NetAdapterBinding -InterfaceAlias * -ComponentID ms_tcpip6 -Verbose

Write-Host -ForegroundColor Cyan "Select your management adapter. (to set IP, DNS, GW)"
$mgmtNic = $null
$mgmtNic = show-Menu -MenuItems $(get-netadapter | sort-object MacAddress) -MenuItemFormatter { "{0}`t{1}`t{2}`t{3}" -f $args.MacAddress, $args.Name, $args.InterfaceDescription, $args.LinkSpeed}

do {
    $iPAddress = Read-Host -Prompt "Enter a valid IP address for the management adapter"
} while (-not ($iPAddress -match "\d\d?\d?\.\d\d?\d?\.\d\d?\d?\.\d\d?\d?"))

do {
    $dnsIP = Read-Host -Prompt "Enter a valid DNS IP address"
} while (-not ($dnsIP -match "\d\d?\d?\.\d\d?\d?\.\d\d?\d?\.\d\d?\d?"))

do {
    $prefixLength = Read-Host -Prompt "Enter the IP's subnet mask as prefix (e.g. 24 for 255.255.255.0)"
} while (-not ($prefixLength -match [regex]'^[1-2][0-9]?$|^[3][0-2]?$|^[4-9]$'))

do {
    $defaultGateway = Read-Host -Prompt "Enter a valid defaultGateway IP address"
} while (-not ($defaultGateway -match "\d\d?\d?\.\d\d?\d?\.\d\d?\d?\.\d\d?\d?"))


Set-NetIPInterface -InterfaceAlias $($mgmtNic.Name) -Dhcp Enabled -Verbose
Start-Sleep 3
Set-NetIPInterface -InterfaceAlias $($mgmtNic.Name) -Dhcp Disabled -Verbose
New-NetIPAddress -InterfaceAlias $($mgmtNic.Name) -IPAddress $iPAddress -AddressFamily IPv4 -PrefixLength $prefixLength -Verbose -DefaultGateway $defaultGateway
Set-DnsClientServerAddress -InterfaceAlias $($mgmtNic.Name) -ServerAddresses $dnsIP
Disable-NetAdapterBinding -InterfaceAlias $($mgmtNic.Name) -ComponentID ms_tcpip6     #disable IPv6


<#
Write-Host -ForegroundColor Cyan "Disabling DHCP on all other adapters."
$toDisableNics = show-Menu -MenuItems $(get-netadapter | sort-object MacAddress) -MenuItemFormatter { "{0}`t{1}`t{2}" -f $args.MacAddress, $args.Name, $args.InterfaceDescription} -multiselect
foreach ($nic in $toDisableNics)
{
    Disable-NetAdapter -InputObject $nic -Verbose
}
#>

<#
$SMB2NetAdapterName = "SMB2"
Set-NetIPInterface -InterfaceAlias $SMB2NetAdapterName -Dhcp Enabled -Verbose
Start-Sleep 3
Set-NetIPInterface -InterfaceAlias $SMB2NetAdapterName -Dhcp Disabled -Verbose
New-NetIPAddress -InterfaceAlias $SMB2NetAdapterName -IPAddress $($NodeInfo.$($env:COMPUTERNAME).SMB2IP) -AddressFamily IPv4 -PrefixLength $($NodeInfo.$($env:COMPUTERNAME).SMBMask) -Verbose
Set-DnsClient -InterfaceAlias $SMB2NetAdapterName -RegisterThisConnectionsAddress $false
Disable-NetAdapterBinding -InterfaceAlias $SMB2NetAdapterName -ComponentID ms_tcpip6      #disable IPv6
#>
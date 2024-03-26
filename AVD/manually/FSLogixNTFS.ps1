$DomainName = "myavd"   #pls enter your domain name.

#1st remove all exiting permissions.
$acl = Get-Acl "\\Sofs\fslogix1"

$acl.Access | % { $acl.RemoveAccessRule($_) }
$acl.SetAccessRuleProtection($true, $false)
$acl | Set-Acl
#add full control for 'the usual suspects'
$users = @("$DomainName\Domain Admins", "System", "Administrators", "Creator Owner" )
foreach ($user in $users) {
    $new = $user, "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow"
    $accessRule = new-object System.Security.AccessControl.FileSystemAccessRule $new
    $acl.AddAccessRule($accessRule)
    $acl | Set-Acl 
}

#add read & write on parent folder ->required for FSLogix - no inheritence
$allowWVD = "AVD Users", "ReadData, AppendData, ExecuteFile, ReadAttributes, Synchronize", "None", "None", "Allow"
$accessRule = new-object System.Security.AccessControl.FileSystemAccessRule $allowWVD
$acl.AddAccessRule($accessRule)
$acl | Set-Acl 
<#   
.SYNOPSIS   
	Forces a GPUpdate, gets gpresults, and opens it
.AUTHOR
	CircaLucid
#>
# Elevate to Administrator
If (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")){   
    $arguments = "& '" + $myinvocation.mycommand.definition + "'"
    Start-Process powershell -Verb runAs -ArgumentList $arguments
    Break
}
Invoke-Expression "C:\Windows\System32\gpupdate.exe /force"
Invoke-Expression "gpresult /z > `"$($env:userprofile)\Desktop\GPUpdate.txt`""
Invoke-Expression "start notepad `"$($env:userprofile)\Desktop\GPUpdate.txt`""


<#   
.SYNOPSIS   
	Disables/Enables the primary network interface
.AUTHOR
	CircaLucid
#>
If (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")){
    $arguments = "& '" + $myinvocation.mycommand.definition + "'"
    Start-Process powershell -Verb runAs -ArgumentList $arguments
    Break}
[array]$wmi = Get-WmiObject -Class Win32_NetworkAdapter -filter "Name LIKE 'Intel%'"
if($wmi.Count -ne 1){
    Write-Error "Wrong number of NICs: $($wmi.Count)";
    break;
}
$wmi[0].Disable()
Start-Sleep 2
$wmi[0].Enable()


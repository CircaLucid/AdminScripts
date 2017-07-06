<#
.SYNOPSIS
	Creates a Windows Remote Assistanct file and emails RemoteAssistance for help
.AUTHOR
	CircaLucid
#>
$comp = $env:COMPUTERNAME
$user = [Environment]::UserName
$filename = "{3}\WindowsRemoteAssistance_{0:yyyyMMddHHmmss}_{1}_{2}.msrcIncident" -f (Get-Date),$comp,$user,$env:temp
C:\Windows\system32\msra.exe /saveasfile $filename "HelpPlease"
if(!(Test-Path $filename)){Sleep 2}
if(!(Test-Path $filename)){Sleep 2}
"Sending email"
$body = "$comp Remote Assistance Requested Pass:HelpPlease"
Send-MailMessage RemoteAssistance@domain.com $body $body smtp.domain.com -From "$user@domain.com" -Attachment $filename
"Done"
Sleep 5


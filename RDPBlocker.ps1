<#   
.SYNOPSIS   
	Script that adds IPs to a list in the firewall of IPs to block
.NOTES
	Create an inbound firewall rule named BlockAttackers. Run this script every 5 minutes.
.AUTHOR
	CircaLucid
#>
Function Set-Firewall-IPs($ba,$ips){
    "$(Get-Date -f HH:mm:ss) Set the firewall rule IPs"
    $ba.RemoteAddresses = [string]::Join(",", $ips.ToArray()).TrimEnd(',')
}

$Logfile = "C:\ProgramData\RDPBlocker.log"
$HistFile = "C:\ProgramData\RDPBlocker_History.log"
$tstamp = "{0:yyyyMMdd HHmmss}" -f (Get-Date)
$threshold = 10
$subnet = "10.5."
Start-Transcript -Path $Logfile

### Create a starter array
$ips = New-Object System.Collections.ArrayList
$ips.Add("175.45.176.1") # Have to have 1 IP to start. Blocking N Korea
### Get firewall rule named 'BlockAttackers' (must be created manually)
$ba = (New-object -comObject HNetCfg.FwPolicy2).rules | where {$_.Name -eq 'BlockAttackers'}
### select Ip addresses that have audit failure in past 5 minute
"$(Get-Date -f HH:mm:ss) Select Ip addresses that have audit failure in past 5 mninutes"
$DT = [DateTime]::Now.AddMinutes(-5)
$events = Get-EventLog -LogName 'Security' -InstanceId 4625 -After $DT -ErrorAction SilentlyContinue
if(!$events){
    "$(Get-Date -f HH:mm:ss) No events found"
    Set-Firewall-IPs $ba $ips
    Stop-Transcript
    return
}
$events = $events | Select-Object @{n='IpAddress';e={$_.ReplacementStrings[-2]} },@{n='TargetUserName';e={$_.ReplacementStrings[5]} }
### Get non-local adresses, that have too many failed logins
"$(Get-Date -f HH:mm:ss) Get non-local adresses, that have more than $threshold wrong logins"
$newIpsUnfiltered = $events | Group-Object -property IpAddress | where {$_.Count -gt $threshold -and !$_.Name.contains($subnet) -and $_.Name.contains('.')} | Select -property Name
$newIpsFiltered = New-Object System.Collections.ArrayList
$newIpsUnfiltered|%{if($ips -notcontains $_.Name){$newIpsFiltered.Add($_.Name)}} | out-null
$newIpsFiltered|%{$ips.Add($_)} | out-null
### Remove safe IPs
"$(Get-Date -f HH:mm:ss) Remove safe IPs"
$safe=Get-Contents "Safe-IPs.txt"
$safe|%{if($ips -contains $_){$ips.Remove($_)}}
"$(Get-Date -f HH:mm:ss) $($ips.Count) IPs"
### Set the firewall rule IPs
Set-Firewall-IPs $ba $ips
### Log failed logins
$logged = @()
foreach($event in $events){
    if($newIpsFiltered -notcontains $event.IpAddress){ continue }
    $key = "$($event.IpAddress) $($event.TargetUserName)"
    if($logged -contains $key){ continue }
    $logged += $key
    Add-Content $HistFile "$tstamp $key"
}
### Write an event log message
$msg = " $($newIpsFiltered.Count) new IPs to block"
"$(Get-Date -f HH:mm:ss) $msg"
if($newIpsFiltered.Count -gt 1){
    "$(Get-Date -f HH:mm:ss) Writing an event log message"
    Write-Eventlog -LogName Application -Source "RDPBlocker" -EventID 1 -Message $msg -EntryType Warning
}
Stop-Transcript


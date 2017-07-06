<#
.SYNOPSIS
	Runs a wbadmin backup and emails report
.NOTES
	Adjust myinclude, myexclude, and mynonRecurseExclude to your needs.
.AUTHOR
	CircaLucid
#>
Function Dedupe([string[]] $data){
    [string[]]$output = @();
    for ($i = 0; $i -le $data.Length; $i++){
        if($i -ge 2){
            if($data[$i] -eq $data[$i - 1]){ continue; }
            if($data[$i] -eq $data[$i - 2]){ continue; }
        }
        $output += $data[$i]
    }
    $output
}
# Present the Transcript better
$pshost = Get-Host
$pshost.ui.rawui.buffersize = New-Object System.Management.Automation.Host.Size(400, 3000)
# Setup variables
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition
$Logfile = "$scriptPath\Backup.log"
$comp = $env:COMPUTERNAME
$status = "[Success]"
Start-Transcript -Path $Logfile
Write-Host (Get-Date -Format o)
# Show most recent successful backup
$events = Get-WinEvent -FilterHashtable @{LogName="Microsoft-Windows-Backup";Id=4} -MaxEvents 1
if($events.Length -eq 0){
    "No recent backup completed successfully"
} else {
    "Last successful backup: $($events.TimeCreated.ToString("o"))"
}
# Run the backup
$backupTarget="-backupTarget:`"\\bcafs\Backups\$comp-1`""



$myinclude="-include:`"\\?\Volume{b07d0609-ffff-ffff-ffff-806e6f6e6963}\,C:,D:`""
$myexclude="-exclude:`"D:\*.wrk,D:\*.archive,D:\*.bak,D:\*.ldf,D:\*.mdf,D:\*.trn,D:\Debug,D:\inetpub\logs\*.log`""
$mynonRecurseExclude="-nonRecurseExclude:`"D:\pagefile.sys`""



$cmd = "C:\Windows\System32\wbadmin.exe start backup $backupTarget $myinclude $myexclude $mynonRecurseExclude -systemState -vssFull -quiet 2>&1"
Write-Host "$cmd`r`n"
[string[]]$res = Invoke-Expression $cmd
$res = Dedupe $res
[string]$res = $res -join "`r`n"
if($res.Contains("ERROR")){ $status="[Warning]" }
if($res.Contains("backup operation completed with errors")){ $status="[Warning]" }
if($res.Contains("SYSTEMSTATEBACKUP")){ $status="[Failed]" }
Write-Host "$res`r`n"
# Check event log for status
$events = Get-WinEvent -LogName "Microsoft-Windows-Backup"
if($events.Length -eq 0){
    $status="[Failed]"
} else {
    $date = $events[0].TimeCreated.Date
    "Checking $date"
    foreach($event in $events){
        Write-Host $event.Message
        if($event.TimeCreated.Date -ne $date){ break; }
        if($event.Id -eq 5 ){ $status = "[Failed] " ; break; }
        if($event.Id -eq 8 ){ $status = "[Failed] " ; break; }
        if($event.Id -eq 23){ $status = "[Warning] "; break; }
        if($event.Id -eq 4 ){                         break; }
    }
}
Write-Host (Get-Date -Format o)
Write-Host "`r`nSending email`r`n"
# Send email
$user = [Environment]::UserName
$body = [string]::join("`r`n", (Get-Content $Logfile))
Send-MailMessage alert@domain.com "$status $comp WSB backup" $body smtp.bondinvestor.com -From "$user <$user@domain.com>"
Stop-Transcript


<#   
.SYNOPSIS   
	Generates a script of SQL commands to restore a database and tlogs.
.AUTHOR
	CircaLucid
#>
Function Find-SQLBackup-Path($src){
    foreach($path in "K:\Batch\SQLBackups\$src","D:\Batch\SQLBackups\$src","D:\Batch\SQLBackups2\$src"){
        if(Test-Path $path){ $path; break }
    }
}
(Get-Host).ui.rawui.buffersize = New-Object System.Management.Automation.Host.Size(400, 3000)
$Logfile = $env:temp+'\'+[System.IO.Path]::GetRandomFileName()
Start-Transcript -Path $Logfile
$src = Read-Host -Prompt "Source Database?"
$dst = Read-Host -Prompt "Destination Database? (Empty if same)"
if([string]::IsNullOrEmpty($dst)){ $dst = $src; }
$path = Find-SQLBackup-Path $src
if(!$path){
    "Path not found: $path"
    Stop-Transcript
    Start-Sleep 5
    break
}
$lastdb = Get-ChildItem $path -filter "*.bak"
$count1 = $lastdb.Count
$lastdb = $lastdb | Sort-Object LastWriteTime -Descending | Select-Object -First 1
"Restoring DB backup 1/$count1 from $($lastdb.LastWriteTime)"
$lasttl = Get-ChildItem $path -filter "*.trn"
$count1 = $lasttl.Count
$lasttl = Get-ChildItem $path -filter "*.trn" | Where-Object { $_.LastWriteTime -gt $lastdb.LastWriteTime }
$count2 = $lasttl.Count
$date1 = $lasttl | Sort-Object LastWriteTime | Select-Object -First 1
$date2 = $lasttl | Sort-Object LastWriteTime -Descending | Select-Object -First 1
"Restoring TLOG backups $count2/$count1 from $($date1.LastWriteTime) to $($date2.LastWriteTime)"
"`r`n`r`n`r`n"
"RESTORE DATABASE [$dst] FROM  DISK = N'$($lastdb.Fullname)' WITH  FILE = 1,  MOVE N'$src' TO N'D:\DATA\$dst.mdf',  MOVE N'$($src)_log' TO N'J:\TLOG\$dst.ldf',  NORECOVERY,  NOUNLOAD,  REPLACE,  STATS = 10"
foreach($tl in $lasttl){
    "RESTORE LOG [$dst] FROM  DISK = N'$($tl.Fullname)' WITH  FILE = 1,  NORECOVERY,  NOUNLOAD,  STATS = 10"
}
"RESTORE DATABASE [$dst] WITH RECOVERY"
Stop-Transcript
notepad $Logfile
Start-Sleep 1
if(Test-Path $Logfile){Remove-Item $Logfile}


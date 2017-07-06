<#
.SYNOPSIS
	Retrieves list of computers with stale virus definitions. Scripts commands to force updates.
.NOTES
	--Add user as DB reader
	USE CM_BOSca
	ALTER ROLE [db_datareader] ADD MEMBER [DOMAIN\user]
.AUTHOR
	CircaLucid
#>
# http://ssrs01/Reports/Pages/Report.aspx?ItemPath=%2fConfigMgr_BOS%2fEndpoint+Protection%2fAntimalware+overall+status+and+history&ViewMode=Detail
$Logfile = "\\fs\Documents\Department - Technology\@AutomatedReports\Get-ScepCompliance.log"
Start-Transcript -Path $Logfile

$sql="SELECT [SignatureUpTo1DayOld]
,[SignatureUpTo3DaysOld]
,[SignatureUpTo7DaysOld]
,[SignatureOlderThan7Days]
,EpAtRisk
,s.Name0,s.[Operating_System_Name_and0]
FROM v_EndpointProtectionStatus eps
JOIN v_R_System s ON eps.ResourceID = s.ResourceID
WHERE EpEnabled=1"
$SqlConnection = New-Object System.Data.SqlClient.SqlConnection
$SqlConnection.ConnectionString = "Server=SSRS01;Integrated Security=SSPI;Database=CM_BOS;"
$SqlCmd = New-Object System.Data.SqlClient.SqlCommand
$SqlCmd.CommandText = $sql
$SqlCmd.Connection = $SqlConnection
$SqlAdapter = New-Object System.Data.SqlClient.SqlDataAdapter
$SqlAdapter.SelectCommand = $SqlCmd
$ds = New-Object System.Data.DataSet
Write-Host "Getting devices" -ForegroundColor Yellow
$SqlAdapter.Fill($ds)
$SqlConnection.Close()
$rows=@()
foreach($dr in $ds.Tables[0].Rows){
    $obj = New-Object -TypeName PSObject -Property @{Name=$dr.Name0;Risk=1;Status="SignatureUpTo1DayOld";OS=$dr.Operating_System_Name_and0}
    if($dr.SignatureUpTo3DaysOld -eq 1){ $obj.Risk=2;$obj.Status="SignatureUpTo3DaysOld" }
    if($dr.SignatureUpTo7DaysOld -eq 1){ $obj.Risk=3;$obj.Status="SignatureUpTo7DaysOld" }
    if($dr.SignatureOlderThan7Days -eq 1){ $obj.Risk=4;$obj.Status="SignatureOlderThan7Days" }
    if($dr.Operating_System_Name_and0 -match "6."){ $obj.OS=7 }
    if($dr.Operating_System_Name_and0 -match "10.0"){ $obj.OS=10 }
    $rows+=$obj
}
if(($rows|?{$_.Risk -ge 3}).Count -eq 0){
    Write-Host "No AtRisk or NearRisk computers found" -ForegroundColor Green
    Stop-Transcript
    break
}

Write-Host "Listing AtRisk and NearRisk computers:"
$rows|?{$_.Risk -ge 3}|Sort-Object Risk,Name -Descending|Format-Table Name,Risk,Status,OS

$chunksize=5
$names=($rows|?{$_.Risk -ge 3 -and $_.OS -eq 10}).Name
if($names.Count -gt 0){
    Write-Host "Copy the file to each computer:"
    Write-Host "`t`$src=`"\\msc01\SCCMDeploySource\EndpointProtectionFileShare\x64\mpam-d.exe`""
    Write-Host "Commands to update Win10 machines:"
    $chunks=@()
    for($i=0; $i -lt $names.Length; $i+=$chunksize){ $chunks += [string]::Join(",",$names[$i..($i+$chunksize-1)])}
    foreach($chunk in $chunks){
        Write-Host "`tInvoke-Command -Computername $chunk { Update-MpSignature }" }
    Write-Host "If issue persists on these computers:"
    foreach($name in $names){
        Write-Host "`tCopy-Item `$src `"\\$name\C`$\Windows\Temp`" -Force"
        Write-Host "`tInvoke-Command -Computername $name { . `"C:\Windows\Temp\mpam-d.exe`" }" }
}
$names=($rows|?{$_.Risk -ge 3 -and $_.OS -eq 7}).Name
if($names.Count -gt 0){
    Write-Host "Copy the file to each computer:"
    Write-Host "`t`$src=`"\\msc01\SCCMDeploySource\EndpointProtectionFileShare\x64\mpam-d.exe`""
    Write-Host "Commands to update Win7 machines:"
    foreach($name in $names){
        Write-Host "`tCopy-Item `$src `"\\$name\C`$\Windows\Temp`" -Force"
        Write-Host "`tInvoke-Command -Computername $name { . `"C:\Windows\Temp\mpam-d.exe`" }" }
}
$count=($rows|?{$_.Risk -ge 4}).Count
if($count -gt 0){
    Write-Host "Sending email"
    $user = [Environment]::UserName
    $body = "Full log: `"$Logfile`""
    Send-MailMessage InfraAlerts@domain.com "[Warning] Get-ScepCompliance found $count computers at risk" $body smtp.domain.com -From "$user@domain.com"
}
Stop-Transcript


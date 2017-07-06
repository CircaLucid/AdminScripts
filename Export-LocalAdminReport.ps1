<#
.SYNOPSIS
    Downloads Local Admin non-compliant listing to HTML file
.AUTHOR
	CircaLucid
#>
# Download the list report
$url="http://ssrs01/ReportServer?/ConfigMgr_BOS/Compliance and Settings Management/List of assets by compliance state for a configuration baseline&name=CB.LocalAdmin.Workstations&Severity=3&rs:Format=CSV"
$outpath="\\fs\Documents\Department - Technology\@AutomatedReports\Export-LocalAdminReport.csv"
$wc = New-Object System.Net.WebClient
$wc.UseDefaultCredentials=$true
$wc.DownloadFile($url,$outpath)
# Download the individual report details and append to csv
$output=Get-Content $outpath
$output=$output[3..($output.Length-1)]|ConvertFrom-Csv
foreach($line in $output){
    $url="http://ssrs01/ReportServer?/ConfigMgr_BOS/Compliance and Settings Management/Details of non-compliant rules of configuration items in a configuration baseline for an asset&BLname=CB.LocalAdmin.Workstations&Computer=$($line.Details_Table0_MachineName)&Severity=3&UserName=(SYSTEM)&rs:Format=CSV"
    $data=$wc.DownloadString($url)
    $line|Add-Member -Name "Violations" -MemberType NoteProperty -Value ""
    (($data.Split([Environment]::NewLine))[6..($data.Length -1)]|ConvertFrom-Csv).CurrentValue|%{$line.Violations += "$_,"}
    $line|Add-Member -Name "DetailURL" -MemberType NoteProperty -Value $url
    $line
}
$output|ConvertTo-Csv|Set-Content $outpath


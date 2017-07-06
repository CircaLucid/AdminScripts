<#
.SYNOPSIS
    Downloads Software listing to XLSX file
.AUTHOR
	CircaLucid
#>
$url="http://ssrs01/ReportServer?/ConfigMgr_BOS/Asset Intelligence/Software 01A - Summary of installed software in a specific collection&CollectionID=SMS00001&NumberOfRows=100000&Publisher=&rs:Format=EXCELOPENXML"
$wc = New-Object System.Net.WebClient
$wc.UseDefaultCredentials=$true
$wc.DownloadFile($url,"\\fs\Documents\Department - Technology\@AutomatedReports\Export-SoftwareInventory.xlsx")


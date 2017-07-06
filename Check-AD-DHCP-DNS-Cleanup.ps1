<#
.SYNOPSIS   
	Generates a list of AD/DHCP/DNS entries that probably need to be cleaned up
.AUTHOR
	CircaLucid
#>
Function Do-Checks() {
    # Initial values
    $scriptPath = "D:\Batch\DHCP"
    $dnsfile = "$scriptPath\DNS.txt"
    $serverscopes = @("10.5.2.","10.5.4.","10.5.14.","10.5.41.","10.5.64.")
    $IPregex='(?<Address>((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?))'

    # Get the AD registered DHCP servers and export their leases
    Import-Module ActiveDirectory
    $dhcpservers = Get-ADObject -SearchBase "CN=NetServices,CN=Services,CN=Configuration,DC=domain,DC=com" -Filter "objectclass -eq 'dhcpclass' -AND Name -ne 'dhcproot'"
    foreach($server in $dhcpservers){
        $server = $server.Name.Substring(0,$server.Name.IndexOf(".")).ToUpper()
        $path = "$scriptPath\DHCP-$server.txt"
        if(Test-Path $path){Remove-Item $path -Force}
        try{
            Export-DhcpServer -File $path -ComputerName $server -Leases
            "Generated $path"
        }catch{
            "Error generating $path"
        }
    }
    if((Get-ChildItem $scriptPath -Filter "DHCP-*.txt").Count -lt 1){
        "Failed to get any DHCP files"
        return;
    }

    # Merge the DHCP files
    [System.Xml.XMLDocument]$xmldoc = New-Object System.Xml.XmlDocument
    [System.Xml.XMLElement]$xmlroot = $xmldoc.CreateElement("Leases")
    $xmldoc.AppendChild($xmlroot)|Out-Null
    foreach($path in (Get-ChildItem $scriptPath -Filter "DHCP-*.txt")){
        [System.Xml.XMLDocument]$xml = Get-Content $path.FullName
        foreach($scope in $xml.DHCPServer.IPv4.Scopes.ChildNodes){
            foreach($lease in $scope.Leases.ChildNodes){
                $xmlroot.AppendChild($xmldoc.ImportNode($lease,$true))|Out-Null
            }
        }
    }
    $path = "$scriptPath\DHCP.txt"
    if(Test-Path $path){Remove-Item $path}
    $xmldoc.Save("$scriptPath\DHCP.txt")
    "Merged all DHCPs into $path"
    
    # Get the DNS servers and pull all DNS entries from 1 server
    $dnsservers = (Get-WmiObject -Class Win32_NetworkAdapterConfiguration -Filter IPEnabled=TRUE -Property DNSServerSearchOrder).DNSServerSearchOrder
    if(Test-Path $dnsfile){Remove-Item $dnsfile}
    foreach($server in $dnsservers){
        if(Test-Path $dnsfile){continue}
        $serverpath = "\\$server\c$\Windows\system32\dns\dns.txt"
        if(Test-Path $serverpath){Remove-Item $serverpath}
        Export-DnsServerZone -Name "domain.com" -FileName "dns.txt" -ComputerName $server
        Start-Sleep 5
        if(!(Test-Path $serverpath)){continue}
        Move-Item $serverpath $dnsfile -Force
        "Got DNS file from $serverpath"
    }
    if(!(Test-Path $dnsfile)){
        "Failed to get DNS file"
        return;
    }
    
    # Get the reverse DNS PTR records
    $dhcpregex='(?<Zone>((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){2}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?))'
    $dnsptrs = @()
    foreach($server in $dnsservers){
        if($dnsptrs.Count -ne 0){continue}
        $zones = Get-DnsServerZone -ComputerName $server | ? {$_.ZoneName -like '*in-addr.arpa'}
        $records = $zones | Get-DnsServerResourceRecord -ComputerName $server | ?{$_.RecordType -eq "PTR"}
        foreach($record in $records){
            if(!($record.DistinguishedName -match $dhcpregex)){continue}
            $name = $record.RecordData.PtrDomainName
            $name = $name.Substring(0,$name.IndexOf(".")).ToUpper()
            if($name -eq "LOCALHOST"){continue}
            $ip = $Matches.Zone.Split('.')
            [array]::Reverse($ip)
            $ip += $record.HostName
            $ip = [string]::Join(".",$ip)
            $dnsptrs += New-Object -TypeName PSObject -Property @{IP=$ip;Name=$name}
        }
    }
    if($dnsptrs.Count -eq 0){
        "Failed to get DNS PTR records"
        return;
    }
    "Retrieved $($dnsptrs.Count) DNS PTRs"
    
    # Parse the AD entries
    $defaultprops = @{Name=$null;AD=$false;DHCP=@();DNS=@();PTR=@();OU=$null;IsNonWorkstation=$false;IsStatic=$true;Comment=""}
    $Search = [adsisearcher]([ADSI]"LDAP://DC=domain,DC=com")
    $Search.Filter = "objectCategory=Computer"
    [System.Collections.ArrayList]$entries = @()
    foreach ($comp in $Search.FindAll()){
        $os = [string]([string]$comp.Properties.Item('operatingSystem')).ToLower()
        if(!($os.StartsWith("windows"))){continue}
        $start = $comp.Path.IndexOf("OU=")
        if($start -eq -1){
            $start = $comp.Path.IndexOf("CN=",10) }
        $ou = $comp.Path.Substring($start, $comp.Path.IndexOf(",",$start + 1) - $start)
        $entry = New-Object -TypeName PSObject -Property $defaultprops
        $entry.AD = $true
        $entry.Name = ([string]$comp.Properties.Item('name')).ToUpper()
        $entry.OU = $ou
        $entries += $entry
    }
    "Finished AD with $($entries.Count) entries"
    
    # Parse the DHCP entries
    $path = "$scriptPath\DHCP.txt"
    [xml]$xml = Get-Content $path
    foreach($lease in $xml.Leases.ChildNodes){
        $name = $lease.HostName
        if([string]::IsNullOrEmpty($name)){$name = $lease.ClientId}
        if($name -imatch ".DOMAIN.COM"){
            $name = $name.Substring(0,$name.IndexOf(".")).ToUpper() }
        $entry = $entries | ?{$_.Name -eq $name}
        if(!$entry){
            $entry = New-Object -TypeName PSObject -Property $defaultprops
            $entry.Name = $name.ToUpper()
            $entries += $entry
        }
        $entry.DHCP += $lease
    }
    "Finished DHCP with $($entries.Count) entries"
    
    # Parse the DNS entries
    $lines = Get-Content $dnsfile
    $name="" # Used to hold comp name when following line contains extra entries for the same name
    foreach($line in ($lines -match "A`t10.")){
        if(!($line -match $IPregex)){continue}
        $address = $Matches.Address
        if($line.StartsWith("@") -or $line.StartsWith(";") -or $line.Length -lt 24){continue}
        if(!$line.StartsWith(" ")){$name = $line.Substring(0,24).Trim().ToUpper()}
        if($name.StartsWith("BATCHGATEWAY")){continue}
        if($name.StartsWith("GATEWAY")){continue}
        $static = $false
        if($line.Substring(24,1) -match "A"){$static = $true}
        $entry = $entries | ?{$_.Name -eq $name}
        if(!$entry){
            $entry = New-Object -TypeName PSObject -Property $defaultprops
            $entry.Name = $name.ToUpper()
            $entries += $entry
        }
        $entry.DNS += New-Object -TypeName PSObject -Property @{IPv4=$address;Name=$name;Static=$static}
    }
    "Finished DNS with $($entries.Count) entries"
    
    # Parse list of DHCP leases for easy comparisons
    $dhcpips = @{}
    foreach($entry in $entries){
        foreach($dhcp in $entry.DHCP){
            if(!$dhcpips.ContainsKey($dhcp.IPAddress)){
                $dhcpips.Add($dhcp.IPAddress,@()) }
            $dhcpips[$dhcp.IPAddress] += $dhcp
        }
    }
    "Extracted $($dhcpips.Count) DHCP records"
    
    # Parse list of DNS records for easy comparisons
    $dnsips = @{}
    $entries|%{$_.DNS | %{
        if(!$dnsips.ContainsKey($_.IPv4)){
            $dnsips.Add($_.IPv4,@()) }
        $dnsips[$_.IPv4] += $_ }
    }
    "Retrieved $($dnsips.Count) DNS IPs"
    
    # Mark PTR records
    $i = 0
    foreach($entry in $entries){
        $dnsptr = $dnsptrs | ?{$_.Name -eq $entry.Name}
        if($dnsptr -and !($entry.PTR -contains $dnsptr)){
            $entry.PTR += $dnsptr;$i++ }
        foreach($dns in $entry.DNS){
            $dnsptr = $dnsptrs | ?{$_.IP -eq $dns.IPv4}
            if($dnsptr -and !($entry.PTR -contains $dnsptr)){
                $entry.PTR += $dnsptr;$i++ }
        }
    }
    "Set $i PTR entries"

    # Mark servers
    $i = 0
    foreach($entry in $entries){
        if($entry.DNS.Count -eq 0){continue}
        if($entry.OU -eq "OU=Domain Controllers"){
            $entry.IsNonWorkstation = $true; $i++}
        if($entry.OU -eq "OU=NSB - Servers"){
            $entry.IsNonWorkstation = $true; $i++}
        if($entry.OU -eq "OU=Servers"){
            $entry.IsNonWorkstation = $true; $i++}
        foreach($dns in $entry.DNS){
            $scope = $dns.IPv4.Substring(0,$dns.IPv4.LastIndexOf(".")+1)
            if($serverscopes -contains $scope){$entry.IsNonWorkstation = $true; $i++}
        }
    }
    "Marked $i entries IsNonWorkstation"

    # Mark entries that have DNS that is only static
    $i = 0
    foreach($entry in $entries){
        if($entry.DNS.Count -eq 0){continue}
        foreach($dns in $entry.DNS){
            if($dns.Static -eq $false){$entry.IsStatic = $false; $i++}
        }
    }
    "Marked $i entries IsStatic=false"
    
    # Do the reports
    $ftad = @{Label="AD"; Expression={$_.AD}; Width=6}
    $ftcomment = @{Label="Comment"; Expression={$_.Comment}}
    $ftdhcp = @{Label="DHCP"; Expression={$_.DHCP};Width=16}
    $ftdns = @{Label="DNS"; Expression={$_.DNS}}
    $ftname = @{Label="Name"; Expression={$_.Name};Width=24}
    $ftou = @{Label="OU"; Expression={$_.OU};Width=24}
    $ftptr = @{Label="PTR"; Expression={$_.PTR}}
    $format =  $ftname,$ftad,$ftou,$ftdhcp,$ftdns,$ftptr
    
    $collect=$entries|Sort-Object Name|?{$_.DHCP.Count -eq 0 -and $_.DNS.Count -eq 0}
    "`r`nAD comps with no DHCP or DNS: $($collect.Count)"
    "    Check if comps exist. Ignore evices that live off network"
    $collect | Format-Table $ftname,$ftou

    $collect=$entries|Sort-Object Name|?{$_.DHCP.Count -eq 0 -and $_.IsStatic -eq $false -and $_.IsNonWorkstation -eq $false}
    "`r`nAD comps with no DHCP: $($collect.Count)"
    "    Comps that live off network?"
    $collect | Format-Table $ftname,$ftad,$ftou,$ftdns
    
    $collect=$entries|Sort-Object Name|?{$_.DHCP.Count -gt 1 -and $_.OU -ne "OU=WIN10_Laptops" -and $_.Name -notmatch "-AP"}
    "`r`nDevices with too many DHCP (-OU=WIN10_Laptops and -'-AP's): $($collect.Count)"
    $collect | Format-Table $format
    
    $collect=$entries|Sort-Object Name|?{$_.DHCP.Count -gt 0 -and $_.DNS.Count -eq 0}
    "`r`nDevices with DHCP but no DNS: $($collect.Count)"
    "    Devices that live off network?"
    $collect | Format-Table $format
    
    $collect=$entries|Sort-Object Name|?{$_.DNS.Count -gt 1 -and $_.IsNonWorkstation -eq $false}
    "`r`nDevices with too many DNS (-IsNonWorkstation): $($collect.Count)"
    $collect | Format-Table $format
    
    $collect=$entries|Sort-Object Name|?{$_.DNS.Count -gt 0 -and $_.PTR.Count -eq 0}
    "`r`nDevices with no PTR: $($collect.Count)"
    "    Missing PTR zones? Update DNS A entry to auto-gen PTR."
    $collect | Format-Table $format
    
    $collect=$entries|Sort-Object Name|?{$_.PTR.Count -gt 1}
    "`r`nDevices with too many PTR: $($collect.Count)"
    "    Ignore if there's multiple DHCP leases or DNS A records"
    $collect | Format-Table $format
    
    $collect=$entries|Sort-Object Name|?{$_.AD -eq $false -and $_.DHCP.Count -gt 0 -and $_.IsNonWorkstation -eq $false}
    "`r`nDHCP with no AD comp: $($collect.Count)"
    $collect | Format-Table $format

    $collect=$entries|Sort-Object Name|?{$_.AD -eq $false -and $_.DNS.Count -gt 0 -and $_.IsNonWorkstation -eq $false}
    "`r`nDNS with no AD comp: $($collect.Count)"
    $collect | Format-Table $format
    
    $collect=$entries|Sort-Object Name|?{$_.AD -eq $false -and $_.PTR.Count -gt 0 -and $_.IsNonWorkstation -eq $false}
    "`r`nPTR with no AD comp: $($collect.Count)"
    $collect | Format-Table $format

    $collect=$dhcpips.GetEnumerator() | Sort-Object -Property name | ?{$_.Value.Count -gt 1}
    "`r`nDHCP IPs with too many devices: $($collect.Count)"
    $collect
    
    $collect=$dnsips.GetEnumerator() | Sort-Object -Property Name | ?{$_.Value.Count -gt 1}
    "`r`nDNS IPs with too many devices: $($collect.Count)"
    $collect | Format-Table @{Label="Name"; Expression={$_.Name};Width=16},@{Label="Value"; Expression={$_.Value}}

    $collect=@()
    foreach($dnsip in $dnsips.GetEnumerator()){
        $dnsptr = $dnsptrs | ?{$_.IP -eq $dnsip.Name}
        if(!$dnsptr){ $collect += $dnsip }
    }
    "`r`nDNS A IP without PTR IP: $($collect.Count)"
    $collect | Sort-Object -Property Name
    
    $collect=@()
    foreach($dnsip in $dnsips.GetEnumerator()){
        $dnsptr = $dnsptrs | ?{$_.Name -eq $dnsip.Value.Name}
        if(!$dnsptr){ $collect += New-Object -TypeName PSObject -Property @{Name=$dnsip.Value.Name;IP=$dnsip.Value.IPv4} }
    }
    "`r`nDNS A with no matching PTR Name: $($collect.Count)"
    $collect | Sort-Object -Property Name | Format-Table @{Label="Name"; Expression={$_.Name};Width=48},IP
    
    $collect=@()
    foreach($dnsptr in $dnsptrs.GetEnumerator()){
        $dnsip = $dnsips.GetEnumerator() | ?{$_.Name -eq $dnsptr.IP}
        if(!$dnsip){ $collect += $dnsptr }
    }
    "`r`nPTR without DNS A IP: $($collect.Count)"
    "    Can delete."
    $collect | Sort-Object -Property IP | Format-Table $ftname,IP

    $collect=@()
    foreach($dnsptr in $dnsptrs.GetEnumerator()){
        $entry = $entries | ?{$_.Name -eq $dnsptr.Name}
        if(!$entry){
            $collect += $dnsptr }
    }
    "`r`nPTR without DNS A: $($collect.Count)"
    $collect | Sort-Object -Property IP | Format-Table $ftname,IP
    
    $collect=@()
    foreach($entry in ($entries|Sort-Object Name|?{$_.DHCP.Count -gt 0 -and $_.DNS.Count -gt 0})){
        $dhcp = @()
        $entry.DHCP | %{$dhcp += $_.IpAddress}
        $dhcp = ($dhcp | Sort-Object) -join ","
        $dns = @()
        $entry.DNS | %{if($dns -notcontains $_.IPv4){$dns += $_.IPv4}}
        $dns = ($dns | Sort-Object) -join ","
        if($dns -ne $dhcp){
            $entry.Comment = "$dhcp != $dns"
            $collect += $entry
        }
    }
    "`r`nDHCP IPs that don't match DNS IPs: $($collect.Count)"
    $collect | Format-Table $ftname,@{Label="DHCP != DNS"; Expression={$_.Comment}}
    
    $collect=@()
    foreach($entry in ($entries|Sort-Object Name|?{$_.DNS.Count -gt 0 -and $_.PTR.Count -gt 0})){
        $dns = @()
        $entry.DNS | %{$dns += $_.IPv4}
        $dns = ($dns | Sort-Object) -join ","
        $ptr = @()
        $entry.PTR | %{if($ptr -notcontains $_.IP){$ptr += $_.IP}}
        $ptr = ($ptr | Sort-Object) -join ","
        if($dns -ne $ptr){
            $entry.Comment = "$dns != $ptr"
            $collect += $entry
        }
    }
    "`r`nDHCP IPs that don't match PTR IPs: $($collect.Count)"
    $collect | Format-Table $ftname,@{Label="DNS != PTR"; Expression={$_.Comment}}

    # TODO: Static DNS in DHCP ranges
    # TODO: Ignore DHCP checks for static entries
}

if($env:COMPUTERNAME -ne "MSC01"){ Write-Error "This script must be run on MSC01"; Start-Sleep -s 5; break; }
# Setup output file
$Logfile = "D:\Batch\DHCP\DHCP.log.txt"
if(Test-Path $Logfile){Remove-Item $Logfile}
(Get-Host).ui.rawui.buffersize = New-Object System.Management.Automation.Host.Size(400, 100)
Start-Transcript -Path $Logfile
Do-Checks
Stop-Transcript
Send-MailMessage alerts@domain.com "$($env:COMPUTERNAME) DHCP" "DHCP" smtp.domain.com -From "$($env:USERNAME)@domain.com" -Attachments $Logfile


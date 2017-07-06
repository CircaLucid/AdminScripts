<#   
.SYNOPSIS   
	Approves needed updates for WSUS and sets deadline for important updates to Workstations group
.NOTES
	I decline all Office x64 updates as this isn't in my environment.
.AUTHOR
	CircaLucid
#>
Function Approve-Updates{
    If (-Not (Import-Module UpdateServices -PassThru -ErrorAction SilentlyContinue)) {
        Add-Type -Path "$Env:ProgramFiles\Update Services\Api\Microsoft.UpdateServices.Administration.dll" -PassThru | Out-Null }
    try{
        $wsus = [Microsoft.UpdateServices.Administration.AdminProxy]::GetUpdateServer()
    }catch{
        Write-Host "$($_.Exception.Message)`r`n"
        return $true
    }
    $groupallcomps = $wsus.GetComputerTargetGroups() | ?{$_.Name -eq 'All Computers'}
    $groupworkstations = $wsus.GetComputerTargetGroups() | ?{$_.Name -eq 'Workstations'}
    $updateScope = New-Object Microsoft.UpdateServices.Administration.UpdateScope
    $updateScope.ApprovedStates = "NotApproved"
    $updateScope.IncludedInstallationStates = "NotInstalled"
    [array]$updates = $wsus.GetUpdates($updateScope)
    $count = $updates.Count
    Write-Host "Need $count updates`r`n"
    # Auto approve/decline updates
    Write-Host "Approved:`r`n"
    foreach($update in $updates){
        # Decline Itanium updates
        if($update.Title -imatch "Itanium"){
            $up = $update.Title;
            $update.Decline();
            Write-Host "Declined: $up`r`n"
            continue
        }
        # Decline x64 office updates
        if($update.Title -imatch "64-Bit"){
            $decline = $false;
            $up = $update.Title
            if($up -imatch "Office"){ $decline = $true; }
            if($up -imatch "Access"){ $decline = $true; }
            if($up -imatch "Excel"){ $decline = $true; }
            if($up -imatch "Lync"){ $decline = $true; }
            if($up -imatch "OneNote"){ $decline = $true; }
            if($up -imatch "Outlook"){ $decline = $true; }
            if($up -imatch "PowerPoint"){ $decline = $true; }
            if($up -imatch "Project"){ $decline = $true; }
            if($up -imatch "Publisher"){ $decline = $true; }
            if($up -imatch "Visio"){ $decline = $true; }
            if($up -imatch "Word"){ $decline = $true; }
            if($decline){
                $update.Decline();
                Write-Host "Declined: $up`r`n"
                continue
            }
        }
        if($update.RequiresLicenseAgreementAcceptance) { $update.AcceptLicenseAgreement() }
        $update.Approve(“Install”,$groupallcomps) | Out-Null
        Write-Host "$($update.Title)`r`n"
    }
    # Set deadlines
    [array]$classifications = @("Critical Updates","Security Updates")
    [datetime]$deadline = Get-Date -Hour "19"
    #  Find next Saturday
    for($i=1; $i -le 7; $i++){ if($deadline.AddDays($i).DayOfWeek -eq 'Saturday'){ $deadline = $deadline.AddDays($i); break } }
    #  Find following Wednesday
    for($i=1; $i -le 7; $i++){ if($deadline.AddDays($i).DayOfWeek -eq 'Wednesday'){ $deadline = $deadline.AddDays($i); break } }
    # Approve updates for Test group
    Write-Host "Approved for $($groupworkstations.Name) group with Deadline: $deadline`r`n"
    foreach($update in $updates){
        if($classifications.Contains($update.UpdateClassificationTitle)) {
            $update.Approve(“Install”,$groupworkstations,$deadline) | Out-Null
            Write-Host "$($update.Title)`r`n"
        }
    }
    if($count -gt 0) { return $true }
}
Function Decline-Superseded{
    If (-Not (Import-Module UpdateServices -PassThru -ErrorAction SilentlyContinue)) { Add-Type -Path "$Env:ProgramFiles\Update Services\Api\Microsoft.UpdateServices.Administration.dll" -PassThru | Out-Null }
    try{
        $wsus = [Microsoft.UpdateServices.Administration.AdminProxy]::GetUpdateServer()
    }catch{
        Write-Host "$($_.Exception.Message)`r`n"
        return $true
    }
    $groupallcomps = $wsus.GetComputerTargetGroups() | ?{$_.Name -eq 'All Computers'}
    $updateScope = New-Object Microsoft.UpdateServices.Administration.UpdateScope
    $updateScope.ApprovedStates = "LatestRevisionApproved"
    $updateScope.IncludedInstallationStates = "Installed,NotApplicable"
    [array]$updates = $wsus.GetUpdates($updateScope) | ?{$_.IsSuperseded -eq 'True'}
    $count = $updates.Count
    Write-Host "Declining $count superseded updates`r`n"
    Write-Host "Declined:`r`n"
    foreach($update in $updates){
        Write-Host "$($update.Title)`r`n"
        $update.Decline()
    }
    if($count -gt 0) { return $true }
}
(Get-Host).ui.rawui.buffersize = New-Object System.Management.Automation.Host.Size(400, 3000)
$Logfile = "C:\ProgramData\Approve-Needed-WSUS-Updates.log"
Start-Transcript -Path $Logfile
$sendemailau = Approve-Updates
$sendemailds = Decline-Superseded
if($sendemailau -or $sendemailds){ Write-Host "Sending email`r`n" }
Stop-Transcript
# Send email
if($sendemailau -or $sendemailds){
    $body = "$env:COMPUTERNAME approved $count updates"
    Send-MailMessage alerts@domain.com $body $body smtp.domain.com -From "$env:username@domain.com" -Attachments $Logfile
}


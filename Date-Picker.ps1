<#
.SYNOPSIS
	Displays a date selection form
.EXAMPLE
	# . Date-Picker.ps1
	# $thisdate=Date-Picker
.AUTHOR
	CircaLucid
#>
﻿Function Date-Picker() {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    $f=New-Object Windows.Forms.Form 
    $f.Text="Select a Date" 
    $f.Size=New-Object Drawing.Size @(243,230) 
    $f.StartPosition="CenterScreen"
    $c=New-Object System.Windows.Forms.MonthCalendar 
    $c.ShowTodayCircle=$False
    $c.MaxSelectionCount=1
    $f.Controls.Add($c) 
    $btnOk=New-Object System.Windows.Forms.Button
    $btnOk.Location=New-Object System.Drawing.Point(38,165)
    $btnOk.Size=New-Object System.Drawing.Size(75,23)
    $btnOk.Text="OK"
    $btnOk.DialogResult=[System.Windows.Forms.DialogResult]::OK
    $f.AcceptButton=$btnOk
    $f.Controls.Add($btnOk)
    $btnCl=New-Object System.Windows.Forms.Button
    $btnCl.Location=New-Object System.Drawing.Point(113,165)
    $btnCl.Size=New-Object System.Drawing.Size(75,23)
    $btnCl.Text="Cancel"
    $btnCl.DialogResult=[System.Windows.Forms.DialogResult]::Cancel
    $f.CancelButton=$btnCl
    $f.Controls.Add($btnCl)
    $f.Topmost=$True
    $result=$f.ShowDialog() 
    if ($result -eq [System.Windows.Forms.DialogResult]::OK)
    {
        $date=$c.SelectionStart
        $date.ToShortDateString()
    }
}


# AdminScripts

Several scripts I've written to expedite several business functions. I highly recommend signing everything.
$path="path/to/script.ps1"
$cert=@(Get-ChildItem cert:\CurrentUser\My -Codesigning)[0]
$tss="http://timestamp.verisign.com/scripts/timestamp.dll"
Set-AuthenticodeSignature -Certificate $cert -TimestampServer $tss

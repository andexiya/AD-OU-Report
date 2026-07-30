###############################################################################
# OU_Rapor_Pro.ps1
#
# Active Directory OU Report
#
# Features
# --------
# - OU Based Report
# - Active / Disabled Users
# - Active / Disabled Computers
# - Last Logon Date
# - Never Logged On Computers
# - Computers Older Than 90 / 180 / 365 Days
# - TXT Report
# - HTML Dashboard
#
# Compatible:
# Windows Server 2012 R2
# PowerShell 4+
#
###############################################################################

Import-Module ActiveDirectory

$Desktop = [Environment]::GetFolderPath("Desktop")

$TxtReport  = Join-Path $Desktop "OU_Report.txt"
$HtmlReport = Join-Path $Desktop "OU_Report.html"

$Today = Get-Date

###############################################################################
# FUNCTIONS
###############################################################################

function Get-ComputerStatistics {

    param(
        [array]$Computers
    )

    $Active = @(
        $Computers |
        Where-Object {$_.Enabled}
    ).Count

    $Disabled = @(
        $Computers |
        Where-Object {-not $_.Enabled}
    ).Count

    $Never = @(
        $Computers |
        Where-Object {
            $_.Enabled -and
            !$_.LastLogonTimestamp
        }
    ).Count

    $Old90 = @(
        $Computers |
        Where-Object {
            $_.Enabled -and
            $_.LastLogonTimestamp -and
			([datetime]::FromFileTime($_.LastLogonTimestamp)) -lt $Today.AddDays(-90)
        }
    ).Count

    $Old180 = @(
        $Computers |
        Where-Object {
            $_.Enabled -and
            $_.LastLogonTimestamp -and
			([datetime]::FromFileTime($_.LastLogonTimestamp)) -lt $Today.AddDays(-180)
        }
    ).Count

    $Old365 = @(
        $Computers |
        Where-Object {
            $_.Enabled -and
            $_.LastLogonTimestamp -and
			([datetime]::FromFileTime($_.LastLogonTimestamp)) -lt $Today.AddDays(-365)
        }
    ).Count

    $Newest = $Computers |
		Where-Object {$_.LastLogonTimestamp} |
		Sort-Object LastLogonTimestamp -Descending |
		Select-Object -First 1

    if($Newest)
    {
        $LastLogon = [datetime]::FromFileTime($Newest.LastLogonTimestamp).ToString("yyyy-MM-dd HH:mm")
    }
    else
    {
        $LastLogon = "-"
    }

    return [PSCustomObject]@{

        Active     = $Active
        Disabled   = $Disabled
        Never      = $Never

        Old90      = $Old90
        Old180     = $Old180
        Old365     = $Old365

        LastLogon  = $LastLogon

    }

}

###############################################################################

function Get-UserStatistics {

    param(
        [array]$Users
    )

    $Active = @(
        $Users |
        Where-Object {$_.Enabled}
    ).Count

    $Disabled = @(
        $Users |
        Where-Object {-not $_.Enabled}
    ).Count

    return [PSCustomObject]@{

        Active = $Active
        Disabled = $Disabled

    }

}

###############################################################################
# DOMAIN TOTALS
###############################################################################

$AllUsers = Get-ADUser `
    -Filter * `
    -Properties Enabled

$AllComputers = Get-ADComputer `
    -Filter * `
    -Properties Enabled,LastLogonTimestamp,DistinguishedName,OperatingSystem

$AllGroups = Get-ADGroup -Filter *

$DomainComputerStat = Get-ComputerStatistics $AllComputers
$DomainUserStat     = Get-UserStatistics $AllUsers

###############################################################################
# GET OUS
###############################################################################

$OUs = Get-ADOrganizationalUnit `
    -Filter * |
    Sort-Object Name

$Results = @()

###############################################################################
# LOOP
###############################################################################

foreach($OU in $OUs)
{

    Write-Host "Scanning:" $OU.Name -ForegroundColor Cyan

    $Computers = @(
        Get-ADComputer `
            -SearchBase $OU.DistinguishedName `
            -SearchScope OneLevel `
            -Filter * `
            -Properties Enabled,LastLogonTimestamp
    )

    $Users = @(
        Get-ADUser `
            -SearchBase $OU.DistinguishedName `
            -SearchScope OneLevel `
            -Filter * `
            -Properties Enabled
    )

    $Groups = @(
        Get-ADGroup `
            -SearchBase $OU.DistinguishedName `
            -SearchScope OneLevel `
            -Filter *
    )

    $ChildOUs = @(
        Get-ADOrganizationalUnit `
            -SearchBase $OU.DistinguishedName `
            -SearchScope OneLevel `
            -Filter *
    )

    $Objects = @(
        Get-ADObject `
            -SearchBase $OU.DistinguishedName `
            -SearchScope OneLevel `
            -Filter *
    )

    $CompStat = Get-ComputerStatistics $Computers
    $UserStat = Get-UserStatistics $Users
	    $Results += [PSCustomObject]@{

        OUName              = $OU.Name
        DistinguishedName   = $OU.DistinguishedName

        TotalObjects        = $Objects.Count

        Computers           = $Computers.Count
        ActiveComputers     = $CompStat.Active
        DisabledComputers   = $CompStat.Disabled

        NeverLoggedOn       = $CompStat.Never

        Old90Days           = $CompStat.Old90
        Old180Days          = $CompStat.Old180
        Old365Days          = $CompStat.Old365

        LastLogonDate       = $CompStat.LastLogon

        Users               = $Users.Count
        ActiveUsers         = $UserStat.Active
        DisabledUsers       = $UserStat.Disabled

        Groups              = $Groups.Count

        ChildOUs            = $ChildOUs.Count

    }

}

###############################################################################
# TXT REPORT
###############################################################################

$Report = @()

$Report += "==============================================================="
$Report += "ACTIVE DIRECTORY OU REPORT"
$Report += "==============================================================="
$Report += ""
$Report += "Generated : $($Today.ToString('yyyy-MM-dd HH:mm:ss'))"
$Report += "Domain    : $((Get-ADDomain).DNSRoot)"
$Report += ""

$Report += "==================== DOMAIN SUMMARY ===================="

$Report += "Total OU                 : $($OUs.Count)"
$Report += "Total Users              : $($AllUsers.Count)"
$Report += "Active Users             : $($DomainUserStat.Active)"
$Report += "Disabled Users           : $($DomainUserStat.Disabled)"

$Report += ""

$Report += "Total Computers          : $($AllComputers.Count)"
$Report += "Active Computers         : $($DomainComputerStat.Active)"
$Report += "Disabled Computers       : $($DomainComputerStat.Disabled)"

$Report += ""

$Report += "Never Logged On          : $($DomainComputerStat.Never)"
$Report += "Inactive 90 Days         : $($DomainComputerStat.Old90)"
$Report += "Inactive 180 Days        : $($DomainComputerStat.Old180)"
$Report += "Inactive 365 Days        : $($DomainComputerStat.Old365)"

$Report += ""

$Report += "Total Groups             : $($AllGroups.Count)"

$Report += ""
$Report += "==============================================================="
$Report += ""

$Results |
Sort-Object OUName |
Format-Table `
OUName,
TotalObjects,
Computers,
ActiveComputers,
DisabledComputers,
NeverLoggedOn,
Old90Days,
Old180Days,
Old365Days,
LastLogonDate,
Users,
ActiveUsers,
DisabledUsers,
Groups,
ChildOUs `
-AutoSize |
Out-String |
ForEach-Object{

    $Report += $_

}
###############################################################################
# 90+ DAYS INACTIVE COMPUTERS
###############################################################################

$Report += ""
$Report += "==============================================================="
$Report += "90+ DAYS INACTIVE COMPUTERS"
$Report += "==============================================================="
$Report += ""

$AllComputers |
Where-Object{
    $_.Enabled -and
    $_.LastLogonTimestamp -and
    ([datetime]::FromFileTime($_.LastLogonTimestamp)) -lt $Today.AddDays(-90)
} |
Sort-Object LastLogonTimestamp |
Select-Object `
Name,
OperatingSystem,
@{
Name="LastLogon"
Expression={
    [datetime]::FromFileTime($_.LastLogonTimestamp)
}
},
@{
Name="Days"
Expression={
    (New-TimeSpan `
        -Start ([datetime]::FromFileTime($_.LastLogonTimestamp)) `
        -End $Today).Days
}
},
@{
Name="OU"
Expression={
    ($_.DistinguishedName -replace '^CN=.*?,')
}
} |
Format-Table -AutoSize |
Out-String |
ForEach-Object{

    $Report += $_

}
###############################################################################
# 180+ DAYS INACTIVE COMPUTERS
###############################################################################

$Report += ""
$Report += "==============================================================="
$Report += "180+ DAYS INACTIVE COMPUTERS"
$Report += "==============================================================="
$Report += ""

$AllComputers |
Where-Object{
    $_.Enabled -and
    $_.LastLogonTimestamp -and
    ([datetime]::FromFileTime($_.LastLogonTimestamp)) -lt $Today.AddDays(-180)
} |
Sort-Object LastLogonTimestamp |
Select-Object `
Name,
OperatingSystem,
@{
Name="LastLogon"
Expression={
    [datetime]::FromFileTime($_.LastLogonTimestamp)
}
},
@{
Name="Days"
Expression={
    (New-TimeSpan `
        -Start ([datetime]::FromFileTime($_.LastLogonTimestamp)) `
        -End $Today).Days
}
},
@{
Name="OU"
Expression={
    ($_.DistinguishedName -replace '^CN=.*?,')
}
} |
Format-Table -AutoSize |
Out-String |
ForEach-Object{

    $Report += $_

}
###############################################################################
# 365+ DAYS INACTIVE COMPUTERS
###############################################################################

$Report += ""
$Report += "==============================================================="
$Report += "365+ DAYS INACTIVE COMPUTERS"
$Report += "==============================================================="
$Report += ""

$AllComputers |
Where-Object{
    $_.Enabled -and
    $_.LastLogonTimestamp -and
    ([datetime]::FromFileTime($_.LastLogonTimestamp)) -lt $Today.AddDays(-365)
} |
Sort-Object LastLogonTimestamp |
Select-Object `
Name,
OperatingSystem,
@{
Name="LastLogon"
Expression={
    [datetime]::FromFileTime($_.LastLogonTimestamp)
}
},
@{
Name="Days"
Expression={
    (New-TimeSpan `
        -Start ([datetime]::FromFileTime($_.LastLogonTimestamp)) `
        -End $Today).Days
}
},
@{
Name="OU"
Expression={
    ($_.DistinguishedName -replace '^CN=.*?,')
}
} |
Format-Table -AutoSize |
Out-String |
ForEach-Object{

    $Report += $_

}
###############################################################################
# NEVER LOGGED ON COMPUTERS
###############################################################################

$Report += ""
$Report += "==============================================================="
$Report += "NEVER LOGGED ON COMPUTERS"
$Report += "==============================================================="
$Report += ""

$AllComputers |
Where-Object{
    $_.Enabled -and
    -not $_.LastLogonTimestamp
} |
Sort-Object Name |
Select-Object `
Name,
OperatingSystem,
@{
Name="OU"
Expression={
    ($_.DistinguishedName -replace '^CN=.*?,')
}
} |
Format-Table -AutoSize |
Out-String |
ForEach-Object{

    $Report += $_

}
###############################################################################
# DISABLED COMPUTERS
###############################################################################

$Report += ""
$Report += "==============================================================="
$Report += "DISABLED COMPUTERS"
$Report += "==============================================================="
$Report += ""

$AllComputers |
Where-Object{
    -not $_.Enabled
} |
Sort-Object Name |
Select-Object `
Name,
OperatingSystem,
@{
Name="LastLogon"
Expression={
    if($_.LastLogonTimestamp){
        [datetime]::FromFileTime($_.LastLogonTimestamp)
    }
    else{
        "-"
    }
}
},
@{
Name="OU"
Expression={
    ($_.DistinguishedName -replace '^CN=.*?,')
}
} |
Format-Table -AutoSize |
Out-String |
ForEach-Object{

    $Report += $_

}

$Report | Set-Content $TxtReport -Encoding UTF8

Write-Host ""
Write-Host "TXT Report Saved :" $TxtReport -ForegroundColor Green

###############################################################################
# HTML REPORT
###############################################################################

###############################################################################
# HTML - 90 DAYS INACTIVE TABLE
###############################################################################

$Inactive90Html = ""

$AllComputers |
Where-Object{
    $_.Enabled -and
    $_.LastLogonTimestamp -and
    ([datetime]::FromFileTime($_.LastLogonTimestamp) -lt $Today.AddDays(-90))
} |
Sort-Object LastLogonTimestamp |
ForEach-Object{

    $Last = [datetime]::FromFileTime($_.LastLogonTimestamp)

    $Days = (New-TimeSpan -Start $Last -End $Today).Days

    $OU = $_.DistinguishedName -replace '^CN=.*?,'

    $Inactive90Html += @"
<tr>
<td>$($_.Name)</td>
<td>$($_.OperatingSystem)</td>
<td>$($Last.ToString("yyyy-MM-dd HH:mm"))</td>
<td>$Days</td>
<td style='text-align:left'>$OU</td>
</tr>
"@

}
###############################################################################
# HTML - 180 DAYS INACTIVE TABLE
###############################################################################

$Inactive180Html = ""

$AllComputers |
Where-Object{
    $_.Enabled -and
    $_.LastLogonTimestamp -and
    ([datetime]::FromFileTime($_.LastLogonTimestamp) -lt $Today.AddDays(-180))
} |
Sort-Object LastLogonTimestamp |
ForEach-Object{

    $Last=[datetime]::FromFileTime($_.LastLogonTimestamp)
    $Days=(New-TimeSpan -Start $Last -End $Today).Days
    $OU=$_.DistinguishedName -replace '^CN=.*?,'

    $Inactive180Html+=@"
<tr>
<td>$($_.Name)</td>
<td>$($_.OperatingSystem)</td>
<td>$($Last.ToString("yyyy-MM-dd HH:mm"))</td>
<td>$Days</td>
<td style='text-align:left'>$OU</td>
</tr>
"@

}
###############################################################################
# HTML - 365 DAYS INACTIVE TABLE
###############################################################################

$Inactive365Html = ""

$AllComputers |
Where-Object{
    $_.Enabled -and
    $_.LastLogonTimestamp -and
    ([datetime]::FromFileTime($_.LastLogonTimestamp) -lt $Today.AddDays(-365))
} |
Sort-Object LastLogonTimestamp |
ForEach-Object{

    $Last=[datetime]::FromFileTime($_.LastLogonTimestamp)
    $Days=(New-TimeSpan -Start $Last -End $Today).Days
    $OU=$_.DistinguishedName -replace '^CN=.*?,'

    $Inactive365Html+=@"
<tr>
<td>$($_.Name)</td>
<td>$($_.OperatingSystem)</td>
<td>$($Last.ToString("yyyy-MM-dd HH:mm"))</td>
<td>$Days</td>
<td style='text-align:left'>$OU</td>
</tr>
"@

}
###############################################################################
# HTML - DISABLED COMPUTERS TABLE
###############################################################################

$DisabledHtml=""

$AllComputers |
Where-Object{ -not $_.Enabled } |
Sort-Object Name |
ForEach-Object{

    if($_.LastLogonTimestamp){
        $Last=[datetime]::FromFileTime($_.LastLogonTimestamp).ToString("yyyy-MM-dd HH:mm")
    }
    else{
        $Last="-"
    }

    $OU=$_.DistinguishedName -replace '^CN=.*?,'

    $DisabledHtml+=@"
<tr>
<td>$($_.Name)</td>
<td>$($_.OperatingSystem)</td>
<td>$Last</td>
<td style='text-align:left'>$OU</td>
</tr>
"@

}

$Html = @"

<!DOCTYPE html>

<html>

<head>

<meta charset="utf-8">

<title>OU Report</title>

<style>

body{

font-family:Segoe UI;

background:#f4f4f4;

margin:20px;

}

h1{

text-align:center;

}

.summary{

display:flex;

flex-wrap:wrap;

gap:15px;

margin-bottom:25px;

}

.card{

background:white;

padding:15px;

border-radius:8px;

box-shadow:0 0 5px rgba(0,0,0,.15);

width:220px;

}

.card h2{

margin:0;

font-size:15px;

}

.card p{

font-size:26px;

margin:10px 0 0 0;

font-weight:bold;

color:#1f5fbf;

}

table{

width:100%;

border-collapse:collapse;

background:white;

}

th{

position:sticky;
top:0;
z-index:100;

background:#1f5fbf;

color:white;

padding:8px;

}

td{

padding:7px;

border:1px solid #ddd;

text-align:center;

}

tr:nth-child(even){

background:#f7f7f7;

}

</style>

</head>

<body>

<h1>Active Directory OU Report</h1>

<div class="summary">
<div class="card">
<h2>Total OU</h2>
<p>$($OUs.Count)</p>
</div>

<div class="card">
<h2>Total Users</h2>
<p>$($AllUsers.Count)</p>
</div>

<div class="card">
<h2>Active Users</h2>
<p>$($DomainUserStat.Active)</p>
</div>

<div class="card">
<h2>Disabled Users</h2>
<p>$($DomainUserStat.Disabled)</p>
</div>

<div class="card">
<h2>Total Computers</h2>
<p>$($AllComputers.Count)</p>
</div>

<div class="card">
<h2>Active Computers</h2>
<p>$($DomainComputerStat.Active)</p>
</div>

<div class="card">
<h2>Disabled Computers</h2>
<p>$($DomainComputerStat.Disabled)</p>
</div>

<div class="card">
<h2>Never Logged On</h2>
<p>$($DomainComputerStat.Never)</p>
</div>

<div class="card">
<h2>Inactive 90 Days</h2>
<p style="color:#d35400">$($DomainComputerStat.Old90)</p>
</div>

<div class="card">
<h2>Inactive 180 Days</h2>
<p style="color:#c0392b">$($DomainComputerStat.Old180)</p>
</div>

<div class="card">
<h2>Inactive 365 Days</h2>
<p style="color:red">$($DomainComputerStat.Old365)</p>
</div>

<div class="card">
<h2>Total Groups</h2>
<p>$($AllGroups.Count)</p>
</div>

</div>

<br>

<table id="ReportTable">

<thead>

<tr>

<th>OU</th>
<th>Objects</th>

<th>PC</th>
<th>Active</th>
<th>Disabled</th>

<th>Never</th>

<th>90+</th>
<th>180+</th>
<th>365+</th>

<th>Last Logon</th>

<th>Users</th>
<th>Active</th>
<th>Disabled</th>

<th>Groups</th>

<th>Child OU</th>

</tr>

</thead>

<tbody>

"@

foreach($Row in ($Results | Sort-Object OUName))
{

    if($Row.Old365Days -gt 0)
    {
        $Color365 = "#ffb3b3"
    }
    else
    {
        $Color365 = "white"
    }

    if($Row.Old180Days -gt 0)
    {
        $Color180 = "#ffe0b3"
    }
    else
    {
        $Color180 = "white"
    }

    if($Row.Old90Days -gt 0)
    {
        $Color90 = "#fff6b3"
    }
    else
    {
        $Color90 = "white"
    }

    if($Row.DisabledComputers -gt 0)
    {
        $PCColor = "#ffd6d6"
    }
    else
    {
        $PCColor = "white"
    }

    $Html += @"

<tr>

<td style='text-align:left'>$($Row.OUName)</td>

<td>$($Row.TotalObjects)</td>

<td>$($Row.Computers)</td>

<td>$($Row.ActiveComputers)</td>

<td style='background:$PCColor'>$($Row.DisabledComputers)</td>

<td>$($Row.NeverLoggedOn)</td>

<td style='background:$Color90'>$($Row.Old90Days)</td>

<td style='background:$Color180'>$($Row.Old180Days)</td>

<td style='background:$Color365'>$($Row.Old365Days)</td>

<td>$($Row.LastLogonDate)</td>

<td>$($Row.Users)</td>

<td>$($Row.ActiveUsers)</td>

<td>$($Row.DisabledUsers)</td>

<td>$($Row.Groups)</td>

<td>$($Row.ChildOUs)</td>

</tr>

"@

}

$Html += @"

</tbody>

</table>

<script>

document.querySelectorAll("th").forEach(function(header,index){

header.style.cursor="pointer";

header.addEventListener("click",function(){

let table=header.closest("table");

let rows=Array.from(table.rows).slice(1);

let asc=header.asc=!header.asc;

rows.sort(function(a,b){

let A=a.cells[index].innerText;

let B=b.cells[index].innerText;

let AN=parseFloat(A);

let BN=parseFloat(B);

if(!isNaN(AN)&&!isNaN(BN)){

return asc?AN-BN:BN-AN;

}

return asc
    ? A.localeCompare(B,'tr',{numeric:true})
    : B.localeCompare(A,'tr',{numeric:true});

});

rows.forEach(function(r){

table.tBodies[0].appendChild(r);

});

});

});

</script>

<hr>

<details>

<summary style="font-size:18px;font-weight:bold;cursor:pointer">

90+ Days Inactive Computers ($($DomainComputerStat.Old90))

</summary>

<br>

<table>

<thead>

<tr>

<th>Name</th>
<th>Operating System</th>
<th>Last Logon</th>
<th>Days</th>
<th>OU</th>

</tr>

</thead>

<tbody>

$Inactive90Html

</tbody>

</table>

</details>

<br>

<details>

<summary style="font-size:18px;font-weight:bold;cursor:pointer">

180+ Days Inactive Computers ($($DomainComputerStat.Old180))

</summary>

<br>

<table>

<thead>

<tr>

<th>Name</th>
<th>Operating System</th>
<th>Last Logon</th>
<th>Days</th>
<th>OU</th>

</tr>

</thead>

<tbody>

$Inactive180Html

</tbody>

</table>

</details>

<br>

<details>

<summary style="font-size:18px;font-weight:bold;cursor:pointer">

365+ Days Inactive Computers ($($DomainComputerStat.Old365))

</summary>

<br>

<table>

<thead>

<tr>

<th>Name</th>
<th>Operating System</th>
<th>Last Logon</th>
<th>Days</th>
<th>OU</th>

</tr>

</thead>

<tbody>

$Inactive365Html

</tbody>

</table>

</details>

<br>

<details>

<summary style="font-size:18px;font-weight:bold;cursor:pointer">

Disabled Computers ($($DomainComputerStat.Disabled))

</summary>

<br>

<table>

<thead>

<tr>

<th>Name</th>
<th>Operating System</th>
<th>Last Logon</th>
<th>OU</th>

</tr>

</thead>

<tbody>

$DisabledHtml

</tbody>

</table>

</details>

<br>



</body>

</html>

"@

$Html | Set-Content $HtmlReport -Encoding UTF8

Write-Host ""
Write-Host "HTML Report Saved :" $HtmlReport -ForegroundColor Green

Start-Process $HtmlReport

Write-Host ""
Write-Host "==============================================" -ForegroundColor Green
Write-Host "OU Report Completed Successfully" -ForegroundColor Green
Write-Host "==============================================" -ForegroundColor Green
Write-Host ""
Write-Host "TXT  : $TxtReport"
Write-Host "HTML : $HtmlReport"
Write-Host ""

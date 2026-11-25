# Creates the forward (A) and reverse (PTR) records for the NTNX1 VCF 9 deployment
# on the Windows DNS server. Run on the DC, or anywhere with the DnsServer module
# (RSAT) and rights on the zones:
#   .\create_dns_records.ps1 -WhatIf     # dry run
#   .\create_dns_records.ps1
#   .\create_dns_records.ps1 -DnsServer uk-bhr-p-dc-1
# Re-running is safe: records that already match are left alone.
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$DnsServer = "192.168.10.250",
    [string]$Zone = "jameskilby.cloud",
    [string]$ReverseNetwork = "192.168.100.0/24",
    # Names that already exist with another IP are only replaced if listed here
    # (the ntnx hosts move from 192.168.38.24-26 to VLAN 100)
    [string[]]$ReplaceNames = @("uk-bhr-p-ntnx-1", "uk-bhr-p-ntnx-2", "uk-bhr-p-ntnx-3")
)

$Records = [ordered]@{
    "uk-bhr-p-vcfi-1"      = "192.168.100.9"    # VCF Installer (temporary)
    "uk-bhr-p-ntnx-1"      = "192.168.100.11"
    "uk-bhr-p-ntnx-2"      = "192.168.100.12"
    "uk-bhr-p-ntnx-3"      = "192.168.100.13"
    "uk-bhr-p-sddcm-1"     = "192.168.100.18"   # SDDC Manager
    "uk-bhr-p-vc-2"        = "192.168.100.19"   # Management vCenter
    "uk-bhr-p-vcfops-1"    = "192.168.100.20"   # VCF Operations
    "uk-bhr-p-vcf-msr-1"   = "192.168.100.21"   # Management Services Runtime
    "uk-bhr-p-vcf-flt-1"   = "192.168.100.22"   # Fleet components
    "uk-bhr-p-vcf-int-1"   = "192.168.100.23"   # Instance components
    "uk-bhr-p-vcf-lic-1"   = "192.168.100.24"   # License Server
    "uk-bhr-p-vcf-logs-1"  = "192.168.100.25"   # Log Management (Day 2)
    "uk-bhr-p-vcf-idb-1"   = "192.168.100.27"   # Identity Broker
    "uk-bhr-p-nsx-1"       = "192.168.100.48"   # NSX VIP
    "uk-bhr-p-nsx-1a"      = "192.168.100.49"   # NSX Manager
    "uk-bhr-p-edge-1a"     = "192.168.100.50"   # NSX Edge (Day 2)
    "uk-bhr-p-edge-1b"     = "192.168.100.51"   # NSX Edge (Day 2)
    "uk-bhr-p-vcf-proxy-1" = "192.168.100.55"   # Ops cloud proxy
    "uk-bhr-p-vcf-asr-1"   = "192.168.100.56"   # Automation Services Runtime
    "uk-bhr-p-vcfa-1"      = "192.168.100.57"   # VCF Automation
    "uk-bhr-p-vcfnet-1"    = "192.168.100.58"   # VCF Operations for networks platform (Day 2)
    "uk-bhr-p-vcfnet-c1"   = "192.168.100.59"   # VCF Operations for networks collector (Day 2)
}
# The MSR (.33-.46) and Automation (.65-.70) node pools need no records.

#### DO NOT EDIT BEYOND HERE ####

$ErrorActionPreference = "Stop"
Import-Module DnsServer

Function My-Logger {
    param(
        [Parameter(Mandatory=$true)][String]$message,
        [Parameter(Mandatory=$false)][String]$color="green"
    )
    $timeStamp = Get-Date -Format "MM-dd-yyyy_hh:mm:ss"
    Write-Host -NoNewline -ForegroundColor White "[$timestamp]"
    Write-Host -ForegroundColor $color " $message"
}

Function Get-PtrInfo([string]$ip) {
    $o = $ip.Split(".")
    @{ Zone = "$($o[2]).$($o[1]).$($o[0]).in-addr.arpa"; Name = $o[3] }
}

Function Remove-Ptr([string]$ip, [string]$fqdn) {
    $p = Get-PtrInfo $ip
    if (-not (Get-DnsServerZone -ComputerName $DnsServer -Name $p.Zone -ErrorAction SilentlyContinue)) { return }
    Get-DnsServerResourceRecord -ComputerName $DnsServer -ZoneName $p.Zone -Name $p.Name -RRType Ptr -ErrorAction SilentlyContinue |
        Where-Object { $_.RecordData.PtrDomainName.TrimEnd(".") -eq $fqdn } |
        ForEach-Object {
            if ($PSCmdlet.ShouldProcess("$($p.Name).$($p.Zone) -> $fqdn", "Remove PTR")) {
                Remove-DnsServerResourceRecord -ComputerName $DnsServer -ZoneName $p.Zone -InputObject $_ -Force
                My-Logger "  removed old PTR $ip -> $fqdn" "yellow"
            }
        }
}

# Reverse zone for VLAN 100
$reverseZone = (Get-PtrInfo "192.168.100.0").Zone
if (-not (Get-DnsServerZone -ComputerName $DnsServer -Name $reverseZone -ErrorAction SilentlyContinue)) {
    if ($PSCmdlet.ShouldProcess($reverseZone, "Create AD-integrated reverse zone")) {
        Add-DnsServerPrimaryZone -ComputerName $DnsServer -NetworkId $ReverseNetwork -ReplicationScope Domain
        My-Logger "Created reverse zone $reverseZone"
    }
}

# Pre-check: refuse to clobber anything not in $ReplaceNames, and IPs already
# claimed by a different name
$conflicts = @()
foreach ($name in $Records.Keys) {
    $ip = $Records[$name]
    $existing = Get-DnsServerResourceRecord -ComputerName $DnsServer -ZoneName $Zone -Name $name -ErrorAction SilentlyContinue |
        Where-Object { $_.RecordType -in @("A", "CNAME") }
    foreach ($r in $existing) {
        $current = if ($r.RecordType -eq "A") { $r.RecordData.IPv4Address.ToString() } else { "CNAME " + $r.RecordData.HostNameAlias }
        if ($current -ne $ip -and $name -notin $ReplaceNames) {
            $conflicts += "$name already exists as $current (wanted $ip)"
        }
    }
    $p = Get-PtrInfo $ip
    Get-DnsServerResourceRecord -ComputerName $DnsServer -ZoneName $p.Zone -Name $p.Name -RRType Ptr -ErrorAction SilentlyContinue |
        Where-Object { $_.RecordData.PtrDomainName.TrimEnd(".") -ne "$name.$Zone" } |
        ForEach-Object { $conflicts += "$ip already has PTR $($_.RecordData.PtrDomainName) (wanted $name.$Zone)" }
}
if ($conflicts) {
    My-Logger "Conflicts found - nothing changed:" "red"
    $conflicts | ForEach-Object { My-Logger "  $_" "red" }
    exit 1
}

foreach ($name in $Records.Keys) {
    $ip = $Records[$name]
    $fqdn = "$name.$Zone"
    $existing = @(Get-DnsServerResourceRecord -ComputerName $DnsServer -ZoneName $Zone -Name $name -RRType A -ErrorAction SilentlyContinue)

    if ($existing.Count -eq 1 -and $existing[0].RecordData.IPv4Address.ToString() -eq $ip) {
        $p = Get-PtrInfo $ip
        $ptr = Get-DnsServerResourceRecord -ComputerName $DnsServer -ZoneName $p.Zone -Name $p.Name -RRType Ptr -ErrorAction SilentlyContinue
        if ($ptr) {
            My-Logger "$fqdn -> $ip already correct" "gray"
            continue
        }
        if ($PSCmdlet.ShouldProcess("$($p.Name).$($p.Zone) -> $fqdn", "Add PTR")) {
            Add-DnsServerResourceRecordPtr -ComputerName $DnsServer -ZoneName $p.Zone -Name $p.Name -PtrDomainName $fqdn
            My-Logger "$fqdn -> $ip (added missing PTR)"
        }
        continue
    }

    # Replace stale A records (the ntnx hosts' old 192.168.38.x addresses) and their PTRs
    foreach ($r in $existing) {
        $old = $r.RecordData.IPv4Address.ToString()
        if ($PSCmdlet.ShouldProcess("$fqdn -> $old", "Remove A")) {
            Remove-DnsServerResourceRecord -ComputerName $DnsServer -ZoneName $Zone -InputObject $r -Force
            My-Logger "  removed old A $fqdn -> $old" "yellow"
        }
        Remove-Ptr $old $fqdn
    }

    if ($PSCmdlet.ShouldProcess("$fqdn -> $ip", "Add A + PTR")) {
        Add-DnsServerResourceRecordA -ComputerName $DnsServer -ZoneName $Zone -Name $name -IPv4Address $ip -CreatePtr
        My-Logger "$fqdn -> $ip"
    }
}

if (-not $WhatIfPreference) {
    My-Logger "Verifying forward and reverse lookups against $DnsServer ..."
    $failed = 0
    foreach ($name in $Records.Keys) {
        $fqdn = "$name.$Zone"
        $ip = $Records[$name]
        $a = (Resolve-DnsName -Server $DnsServer -Name $fqdn -Type A -DnsOnly -ErrorAction SilentlyContinue | Where-Object Type -eq "A").IPAddress
        $ptr = (Resolve-DnsName -Server $DnsServer -Name $ip -Type PTR -DnsOnly -ErrorAction SilentlyContinue).NameHost
        if ($a -ne $ip -or $ptr -ne $fqdn) {
            My-Logger "  FAIL $fqdn : A=$a PTR=$ptr" "red"
            $failed++
        }
    }
    if ($failed -eq 0) { My-Logger "All $($Records.Count) records resolve forward and reverse" }
}

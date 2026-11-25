# Day 2: deploys Log Management (VCF Operations for logs) on NTNX1 through the
# Fleet LCM API, the same workflow as VCF Operations > Build > Lifecycle > VCF
# Management. Unlike Operations for networks it isn't an appliance: it runs on
# the VCF Management Services platform (VMSP), which gains a worker node
# (~12 vCPU / 24 GB) for it. Size and node count can't be reduced afterwards.
#
# Needs the A + PTR record for $LogsFQDN first (scripts/create_dns_records.ps1),
# and the OPS_LOGS binaries in the VIS depot (PROD/COMP/VRLI).
#   pwsh scripts/deploy_ops_logs_ntnx1.ps1               # validate only
#   pwsh scripts/deploy_ops_logs_ntnx1.ps1 -Deploy       # validate + deploy
param([switch]$Deploy)

$RuntimeFQDN = "uk-bhr-p-vcf-msr-1.jameskilby.cloud"   # token endpoint
$FleetFQDN = "uk-bhr-p-vcf-flt-1.jameskilby.cloud"     # Fleet LCM
$VspUser = "admin@vsp.local"
$VspPassword = "VMware123!VMware123!"

# GET https://$FleetFQDN/fleet-lcm/v1/releases lists the available versions
$Version = "9.1.1.0100.25795095"
$LogsFQDN = "uk-bhr-p-vcf-logs-1.jameskilby.cloud"     # 192.168.100.25
$Size = "small"
$NumberOfNodes = 1

$PollSec = 60
$TimeoutSec = 3 * 3600

#### DO NOT EDIT BEYOND HERE ####

$ErrorActionPreference = "Stop"

Function My-Logger {
    param(
        [Parameter(Mandatory=$true)][String]$message,
        [Parameter(Mandatory=$false)][String]$color="green"
    )
    $timeStamp = Get-Date -Format "MM-dd-yyyy_hh:mm:ss"
    Write-Host -NoNewline -ForegroundColor White "[$timestamp]"
    Write-Host -ForegroundColor $color " $message"
}

Function Get-Headers {
    $token = (Invoke-RestMethod -Uri "https://${RuntimeFQDN}/api/v1/identity/token" -Method POST -SkipCertificateCheck `
        -ContentType "application/x-www-form-urlencoded" `
        -Body @{ grant_type = "password"; username = $VspUser; password = $VspPassword }).access_token
    @{ Authorization = "Bearer $token"; Accept = "application/json"; "Content-Type" = "application/json" }
}

# Polls a Fleet LCM task; a fresh token each round, since an install outlives one
Function Wait-FleetTask([String]$id, [String]$what) {
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    $last = ""
    while ($true) {
        # Fleet LCM can return 503 for a while when the VMSP adds a worker and
        # reschedules its own pods (seen deploying Log Management); keep polling.
        try {
            $task = Invoke-RestMethod -Uri "https://${FleetFQDN}/fleet-lcm/v1/tasks/${id}" -Headers (Get-Headers) -SkipCertificateCheck
        } catch {
            if ((Get-Date) -gt $deadline) { throw "${what} timed out (task ${id})" }
            My-Logger "${what}: Fleet LCM unavailable ($($_.Exception.Message)), retrying" "yellow"
            Start-Sleep -Seconds $PollSec
            continue
        }
        $running = ($task.stages | Where-Object { $_.status -eq "RUNNING" } | ForEach-Object { $_.name }) -join ", "
        $line = "${what}: $($task.status) $running"
        if ($line -ne $last) { My-Logger $line; $last = $line }
        switch ($task.status) {
            "SUCCEEDED" { return }
            { $_ -in "FAILED", "CANCELLED" } {
                foreach ($s in @($task) + @($task.stages)) {
                    foreach ($m in $s.messages) {
                        My-Logger "  $($s.name): $($m.message.localizedMessage)" "red"
                    }
                }
                throw "${what} $($task.status) (task ${id})"
            }
        }
        if ((Get-Date) -gt $deadline) { throw "${what} timed out (task ${id})" }
        Start-Sleep -Seconds $(if ($what -eq "Validation") { 5 } else { $PollSec })
    }
}

$headers = Get-Headers
$sddcLcm = (Invoke-RestMethod -Uri "https://${FleetFQDN}/fleet-lcm/v1/sddc-lcms" -Headers $headers -SkipCertificateCheck).sddcLcms |
    Where-Object { $_.isPrimary } | Select-Object -First 1
if (-not $sddcLcm) { throw "No primary SDDC LCM found" }
My-Logger "SDDC LCM $($sddcLcm.sddcGroupName) ($($sddcLcm.id))"

$body = @{
    componentSpecs = @(
        [ordered]@{
            sddcLcmId = $sddcLcm.id
            componentType = "OPS_LOGS"
            deploymentType = "VspComponentSpec"
            version = $Version
            fqdn = $LogsFQDN
            configSpec = [ordered]@{ size = $Size; numberOfNodes = $NumberOfNodes }
        }
    )
} | ConvertTo-Json -Depth 10

My-Logger "Validating Log Management ${Version} (${Size}, ${NumberOfNodes} node) ..."
$task = Invoke-RestMethod -Uri "https://${FleetFQDN}/fleet-lcm/v1/components/validations" -Method POST -Headers $headers -Body $body -SkipCertificateCheck
Wait-FleetTask $task.id "Validation"

if (-not $Deploy) {
    My-Logger "Validation passed. Re-run with -Deploy to install." "yellow"
    exit 0
}

My-Logger "Deploying ..."
$task = Invoke-RestMethod -Uri "https://${FleetFQDN}/fleet-lcm/v1/components" -Method POST -Headers (Get-Headers) -Body $body -SkipCertificateCheck
My-Logger "Install task $($task.id)"
Wait-FleetTask $task.id "Install"
My-Logger "Done: https://${LogsFQDN}"

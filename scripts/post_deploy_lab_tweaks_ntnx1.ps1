# Post-deployment lab tweaks for NTNX1.
#
# Adapted from William Lam's vcf-post-deploy-lab-tweaks.ps1
# (https://github.com/lamw/vmware-scripts/blob/master/powershell/vcf-post-deploy-lab-tweaks.ps1,
# blog: https://williamlam.com/2026/04/automating-lab-optimizations-for-post-deployment-of-vmware-cloud-foundation-vcf.html).
# Changes from upstream:
#   * NTNX1 endpoints and lab passwords.
#   * Acts on ntnx1-mgmt-cl01 by name, not on every vSAN cluster in vCenter.
#   * Silencing vSAN health findings silences whatever is yellow at that
#     moment, so it is skipped unless all 8 vSAN disks are present (ntnx-3's
#     SAS3008 can come up without its SSDs; that must not be silenced).
#   * Each NSX step reports failures instead of carrying on silently.
#
# What it changes (each can be switched off below):
#   vCenter  clear triggered vSAN alarms; silence yellow vSAN health checks
#            plus $AlwaysSilenceChecks (the SSDs/HBA are off the ESA HCL);
#            disable HA admission control
#   NSX      hide the telemetry agreement prompt; accept CEIP; hide the VCF
#            Operations banner for admin; disable the
#            logging.remote_logging_not_configured and
#            capacity.minimum_capacity_threshold alarms; backups every 12 h
#
# Undo: Cluster > Configure > vSphere Availability (admission control),
# Cluster > Monitor > vSAN > Skyline Health (silenced checks), and the same
# NSX APIs / UI settings. Needs pwsh 7 with VMware PowerCLI (incl. the vSAN
# module).

# vCenter
$VCenterFQDN = "uk-bhr-p-vc-2.jameskilby.cloud"
$VCenterUser = "administrator@vsphere.local"
$VCenterPassword = "VMware123!VMware123!"
$ClusterName = "ntnx1-mgmt-cl01"
$ExpectedVsanDisks = 8
# vSAN health checks silenced whatever their colour (TestId without the
# com.vmware.vsan.health.test. prefix). controlleronhcl is red because the
# LSI SAS3008 isn't on the HCL, and a red vSAN health blocks Supervisor.
$AlwaysSilenceChecks = @("controlleronhcl")

$clearVSANHealthAlarms = $true
$silenceVSANHealthFindings = $true
$disableAdmissionControl = $true

# NSX (cluster VIP)
$NSXFQDN = "uk-bhr-p-nsx-1.jameskilby.cloud"
$NSXUser = "admin"
$NSXPassword = "VMware123!VMware123!"

$acceptEula = $true
$acceptCeip = $true
$updateUserPref = $true
$silenceAlarm = $true
$updateBackup = $true
$BackupIntervalSeconds = 43200

#### DO NOT EDIT BEYOND HERE ####

Function My-Logger {
    param(
        [Parameter(Mandatory=$true)][String]$message,
        [Parameter(Mandatory=$false)][String]$color="green"
    )

    $timeStamp = Get-Date -Format "MM-dd-yyyy_hh:mm:ss"

    Write-Host -NoNewline -ForegroundColor White "[$timestamp]"
    Write-Host -ForegroundColor $color " $message"
}

if($clearVSANHealthAlarms -or $silenceVSANHealthFindings -or $disableAdmissionControl) {
    $viConnection = Connect-VIServer $VCenterFQDN -User $VCenterUser -Password $VCenterPassword -WarningAction SilentlyContinue
    $cluster = Get-Cluster -Server $viConnection -Name $ClusterName -ErrorAction Stop

    if($clearVSANHealthAlarms) {
        My-Logger "Clearing triggered alarms on ${ClusterName} ..."
        $alarmMgr = Get-View AlarmManager -Server $viConnection
        foreach ($alarm in $cluster.ExtensionData.TriggeredAlarmState) {
            $alarmMgr.AcknowledgeAlarm($alarm.Alarm, $cluster.ExtensionData.MoRef)
        }
        $alarmSpec = New-Object VMware.Vim.AlarmFilterSpec
        $alarmMgr.ClearTriggeredAlarms($alarmSpec)
    }

    if($silenceVSANHealthFindings) {
        # ESA has no disk groups: count each host's claimed storage-pool devices
        $diskCount = 0
        foreach ($vmhost in ($cluster | Get-VMHost)) {
            $esxcli = Get-EsxCli -VMHost $vmhost -V2
            $diskCount += ($esxcli.vsan.storagepool.list.Invoke() | Measure-Object).Count
        }
        if($diskCount -ne $ExpectedVsanDisks) {
            My-Logger "Skipping vSAN health silencing: found ${diskCount} vSAN disks, expected ${ExpectedVsanDisks}. Fix the missing disks first (ntnx-3 HBA: full power-off)." "yellow"
        } else {
            My-Logger "Silencing yellow and listed vSAN health checks on ${ClusterName} (${diskCount} disks present) ..."
            $vchs = Get-VSANView -Server $viConnection -Id "VsanVcClusterHealthSystem-vsan-cluster-health-system"
            $results = $vchs.VsanQueryVcClusterHealthSummary($cluster.ExtensionData.MoRef, $null, $null, $null, $null, $null, $null, $null, $null)
            $silentChecks = @($AlwaysSilenceChecks)
            foreach ($group in $results.Groups) {
                foreach ($groupTest in $group.GroupTests) {
                    if($groupTest.TestHealth -eq "yellow" -and $silentChecks -notcontains $groupTest.TestId.replace("com.vmware.vsan.health.test.","")) {
                        $silentChecks += $groupTest.TestId.replace("com.vmware.vsan.health.test.","")
                    }
                }
            }
            if($silentChecks.Count -gt 0) {
                My-Logger "  silencing: $($silentChecks -join ', ')"
                $vchs.VsanHealthSetVsanClusterSilentChecks($cluster.ExtensionData.MoRef, $silentChecks, $null) | Out-Null
            } else {
                My-Logger "  nothing to silence"
            }
        }
    }

    if($disableAdmissionControl) {
        My-Logger "Disabling vSphere HA admission control on ${ClusterName} ..."
        $dasSpec = New-Object VMware.Vim.ClusterDasConfigInfo
        $dasSpec.AdmissionControlEnabled = $false
        $spec = New-Object VMware.Vim.ClusterConfigSpecEx
        $spec.DasConfig = $dasSpec
        $task = $cluster.ExtensionData.ReconfigureComputeResource_Task($spec, $true)
        Get-Task -Server $viConnection -Id ("Task-$($task.Value)") | Wait-Task | Out-Null
    }

    Disconnect-VIServer -Server $viConnection -Confirm:$false | Out-Null
}

if($acceptEula -or $acceptCeip -or $updateUserPref -or $silenceAlarm -or $updateBackup) {
    $encoded = [Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("${NSXUser}:${NSXPassword}"))
    $headers = @{
        Authorization = "Basic $encoded"
        "Content-Type" = "application/json"
    }

    # GET an NSX object, let $change modify it, PUT it back.
    Function Update-NsxObject {
        param([String]$path, [ScriptBlock]$change, [Int]$depth = 10)
        $uri = "https://${NSXFQDN}${path}"
        try {
            $spec = Invoke-RestMethod -Uri $uri -Method GET -Headers $headers -SkipCertificateCheck
            & $change $spec
            Invoke-RestMethod -Uri $uri -Method PUT -Headers $headers -Body ($spec | ConvertTo-Json -Depth $depth) -SkipCertificateCheck | Out-Null
        } catch {
            My-Logger "  FAILED ${path}: $($_.Exception.Message)" "red"
        }
    }
}

if($acceptEula) {
    My-Logger "Hiding the NSX telemetry agreement prompt ..."
    Update-NsxObject "/api/v1/telemetry/agreement" { param($s) $s.telemetry_agreement_displayed = $false }
}

if($acceptCeip) {
    My-Logger "Accepting NSX CEIP ..."
    Update-NsxObject "/api/v1/telemetry/config" { param($s) $s.ceip_acceptance = $true }
}

if($updateUserPref) {
    My-Logger "Hiding the VCF Operations banner in NSX (${NSXUser}) ..."
    Update-NsxObject "/api/v1/user-preferences" {
        param($s)
        if (-not ($s.PSObject.Properties.Name -contains "other_preferences")) {
            $s | Add-Member -MemberType NoteProperty -Name "other_preferences" -Value @()
        }
        $pref = $s.other_preferences | Where-Object { $_.key -eq "hideVcfBanner" }
        if ($null -eq $pref) {
            $s.other_preferences += [pscustomobject]@{ key = "hideVcfBanner"; value = $true }
        } else {
            $pref.value = $true
        }
    }
}

if($silenceAlarm) {
    foreach ($event in @("logging.remote_logging_not_configured", "capacity.minimum_capacity_threshold")) {
        My-Logger "Disabling NSX alarm ${event} ..."
        Update-NsxObject "/api/v1/events/${event}" { param($s) $s.is_disabled = $true }
    }
}

if($updateBackup) {
    My-Logger "Setting the NSX backup interval to $($BackupIntervalSeconds / 3600) h ..."
    Update-NsxObject "/api/v1/cluster/backups/config" { param($s) $s.backup_schedule.seconds_between_backups = $BackupIntervalSeconds }
}

My-Logger "Done"

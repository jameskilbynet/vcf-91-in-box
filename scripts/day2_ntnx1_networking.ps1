# Day-2 networking for NTNX1, run after the VCF bring-up succeeds:
#   1. NSX Edge cluster (Edge TEP VLAN 104, Tier-0 uplinks on VLAN 106/107,
#      eBGP AS 65100 <-> mikrotik-sw-1 AS 65000) via the SDDC Manager API
#   2. VLAN 105 VM-Network port group on the management VDS
# sw-1 needs its side of the BGP sessions first (see README).

$SDDCManagerFQDN = "uk-bhr-p-sddcm-1.jameskilby.cloud"
$SDDCManagerUser = "admin@local"
$SDDCManagerPassword = "VMware123!VMware123!"

$VCenterFQDN = "uk-bhr-p-vc-2.jameskilby.cloud"
$VCenterUser = "administrator@vsphere.local"
$VCenterPassword = "VMware123!VMware123!"

$ClusterName = "ntnx1-mgmt-cl01"
$EdgeClusterSpecFile = Join-Path $PSScriptRoot "../config/edge-cluster-ntnx1.json"

$VDSName = "ntnx1-m01-cl01-vds01"
$VMNetworkPortgroup = "ntnx1-vm-network"
$VMNetworkVlan = 105

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

$baseUri = "https://${SDDCManagerFQDN}"

My-Logger "Retrieving access token from SDDC Manager ..."
$body = @{ "username" = $SDDCManagerUser; "password" = $SDDCManagerPassword } | ConvertTo-Json
$token = (Invoke-RestMethod -Uri "${baseUri}/v1/tokens" -Method POST -Body $body -ContentType "application/json" -SkipCertificateCheck).accessToken
$headers = @{ "Authorization" = "Bearer ${token}" }

$cluster = (Invoke-RestMethod -Uri "${baseUri}/v1/clusters" -Headers $headers -SkipCertificateCheck).elements | Where-Object { $_.name -eq $ClusterName }
if (-not $cluster) {
    My-Logger "Cluster $ClusterName not found in SDDC Manager" "red"
    exit 1
}

$spec = Get-Content $EdgeClusterSpecFile -Raw | ConvertFrom-Json
foreach ($node in $spec.edgeNodeSpecs) {
    $node.clusterId = $cluster.id
}
$specBody = $spec | ConvertTo-Json -Depth 10

My-Logger "Validating Edge cluster spec ..."
$validation = Invoke-RestMethod -Uri "${baseUri}/v1/edge-clusters/validations" -Method POST -Body $specBody -ContentType "application/json" -Headers $headers -SkipCertificateCheck
while ($validation.executionStatus -ne "COMPLETED") {
    Start-Sleep 20
    $validation = Invoke-RestMethod -Uri "${baseUri}/v1/edge-clusters/validations/$($validation.id)" -Headers $headers -SkipCertificateCheck
}
if ($validation.resultStatus -ne "SUCCEEDED") {
    My-Logger "Edge cluster validation $($validation.resultStatus):" "red"
    $validation.validationChecks | Where-Object { $_.resultStatus -ne "SUCCEEDED" } | ConvertTo-Json -Depth 10
    exit 1
}

My-Logger "Creating Edge cluster $($spec.edgeClusterName) (this takes a while) ..."
$task = Invoke-RestMethod -Uri "${baseUri}/v1/edge-clusters" -Method POST -Body $specBody -ContentType "application/json" -Headers $headers -SkipCertificateCheck
while ($task.status -in @("PENDING", "Pending", "IN_PROGRESS", "In Progress", "QUEUED", "Queued")) {
    Start-Sleep 60
    $task = Invoke-RestMethod -Uri "${baseUri}/v1/tasks/$($task.id)" -Headers $headers -SkipCertificateCheck
}
if ($task.status -notin @("SUCCESSFUL", "Successful")) {
    My-Logger "Edge cluster task $($task.status) - see SDDC Manager task $($task.id)" "red"
    exit 1
}
My-Logger "Edge cluster $($spec.edgeClusterName) created"

My-Logger "Creating $VMNetworkPortgroup (VLAN $VMNetworkVlan) on $VDSName ..."
$viConnection = Connect-VIServer $VCenterFQDN -User $VCenterUser -Password $VCenterPassword -WarningAction SilentlyContinue
if (-not (Get-VDPortgroup -Server $viConnection -Name $VMNetworkPortgroup -ErrorAction SilentlyContinue)) {
    Get-VDSwitch -Server $viConnection -Name $VDSName | New-VDPortgroup -Name $VMNetworkPortgroup -VlanId $VMNetworkVlan | Out-Null
}
Disconnect-VIServer $viConnection -Confirm:$false

My-Logger "Done"

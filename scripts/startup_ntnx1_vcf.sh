#!/bin/bash
# Brings the NTNX1 VCF 9.1.1 appliances back up once uk-bhr-p-vc-2 is online.
# Run AFTER: hosts powered on, vCenter up, and Cluster -> vSAN -> Restart Cluster done.
# Powers the VMs on bottom-up (reverse of shutdown_ntnx1_vcf.sh), waiting for
# each component to answer before starting the next.
#
# With --vsan it does the vCenter/vSAN part too: run it as soon as the hosts are
# powered on and it waits for vCenter and the hosts to connect, runs vSAN
# Restart Cluster through the vSAN API (vsan_cluster_power.py) if the cluster
# isn't fully powered on, then carries on as below.
#
#   ./startup_ntnx1_vcf.sh --dry-run    # pre-checks + plan, changes nothing
#   ./startup_ntnx1_vcf.sh              # asks for confirmation first
#   ./startup_ntnx1_vcf.sh --yes        # no prompt
#   ./startup_ntnx1_vcf.sh --yes --vsan # wait for vCenter + vSAN Restart Cluster first

export GOVC_URL="${GOVC_URL:-uk-bhr-p-vc-2.jameskilby.cloud}"
export GOVC_USERNAME="${GOVC_USERNAME:-administrator@vsphere.local}"
export GOVC_PASSWORD="${GOVC_PASSWORD:-VMware123!VMware123!}"
export GOVC_INSECURE=1

CLUSTER="/ntnx1-dc/host/ntnx1-mgmt-cl01"
EXPECTED_VSAN_DISKS=8   # 3 + 3 + 2 (ntnx-3 bay 0 is empty)

DOMAIN="jameskilby.cloud"
SDDC_MANAGER_USER="admin@local"
SDDC_MANAGER_PASSWORD="VMware123!VMware123!"
NSX_USER="admin"
NSX_PASSWORD="VMware123!VMware123!"

# Startup order, bottom of the stack first: "name|VM name glob|readiness check|timeout (s)"
# Readiness checks:
#   sddcm     SDDC Manager API issues a token
#   nsx       NSX management cluster status is STABLE
#   http:FQDN https://FQDN/ answers with a status below 500 (a 5xx means the
#             web front end is up but the service behind it isn't yet)
#   tools     VMware Tools running in every VM of the layer
LAYERS=(
    "SDDC Manager|uk-bhr-p-sddcm-1|sddcm|1800"
    "NSX Manager|uk-bhr-p-nsx-1*|nsx|2700"
    "NSX Edges|uk-bhr-p-edge-1*|tools|900"
    "VCF License Server|uk-bhr-p-vcf-lic-1|http:uk-bhr-p-vcf-lic-1|900"
    "VCF management services runtime|uk-bhr-p-vcf-msr-1-*|http:uk-bhr-p-vcf-msr-1|2700"
    "VCF Operations|uk-bhr-p-vcfops-1|http:uk-bhr-p-vcfops-1|1800"
    "VCF Operations cloud proxy|uk-bhr-p-vcf-proxy-1|http:uk-bhr-p-vcf-proxy-1|1200"
    "VCF Operations for networks platform|ops_networks-platform-*|http:uk-bhr-p-vcfnet-1|1800"
    "VCF Operations for networks collector|ops_networks-collector-*|tools|900"
    "VCF Automation|uk-bhr-p-vcf-asr-1-*|http:uk-bhr-p-vcfa-1|3600"
)

# Extra wait after a layer reports ready, so dependent services can settle
SETTLE_SECONDS=120

# --vsan: how long to wait for vCenter, and then every host, to come up after
# the hosts are powered on
VCENTER_WAIT_TIMEOUT=3600

### DO NOT EDIT BEYOND HERE ###

DRY_RUN=false
ASSUME_YES=false
VSAN=false
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=true ;;
        --yes) ASSUME_YES=true ;;
        --vsan) VSAN=true ;;
        *) echo "Unknown option: $arg"; exit 1 ;;
    esac
done

log() { echo -e "[$(date +%H:%M:%S)] $*"; }

command -v govc >/dev/null || { echo "govc not found (brew install govc)"; exit 1; }
VSAN_POWER="$(cd "$(dirname "$0")" && pwd)/vsan_cluster_power.py"

if ${VSAN}; then
    # The hosts have just been powered on: wait for vCenter, then for every
    # host to reconnect (maintenance mode is expected until vSAN restarts).
    log "Waiting for ${GOVC_URL} and the hosts (up to ${VCENTER_WAIT_TIMEOUT}s)"
    waited=0
    while true; do
        if govc about >/dev/null 2>&1; then
            pending=""
            for host in $(govc find "${CLUSTER}" -type h 2>/dev/null); do
                [[ "$(govc object.collect -s "${host}" runtime.connectionState 2>/dev/null)" == "connected" ]] \
                    || pending="${pending} ${host##*/}"
            done
            [[ -n "$(govc find "${CLUSTER}" -type h 2>/dev/null)" && -z "${pending}" ]] && break
        fi
        if (( waited >= VCENTER_WAIT_TIMEOUT )); then
            log "  vCenter or the hosts still not up after ${VCENTER_WAIT_TIMEOUT}s${pending:+ (waiting for:${pending})}"
            exit 1
        fi
        sleep 30
        waited=$((waited + 30))
    done
    log "  vCenter and all hosts connected (${waited}s)"

    cluster_id=$(govc find -i -maxdepth 0 "${CLUSTER}")
    # vCenter's vSAN health service starts a few minutes after the vSphere
    # API does and answers 503 until then, so keep asking.
    until vsan_status=$(python3 -I "${VSAN_POWER}" status "${cluster_id}"); do
        if (( waited >= VCENTER_WAIT_TIMEOUT )); then
            log "  can't read the vSAN cluster power state: ${vsan_status}"
            exit 1
        fi
        log "  vSAN API not ready yet (${vsan_status}), retrying"
        sleep 30
        waited=$((waited + 30))
    done
    if [[ "${vsan_status}" != "clusterPoweredOn" ]]; then
        if ${DRY_RUN}; then
            log "vSAN cluster is ${vsan_status}: a real run starts with vSAN Restart Cluster."
            log "The pre-checks and the VM plan need the restart done first, so this dry run stops here."
            exit 0
        fi
        log "vSAN Restart Cluster on ${CLUSTER##*/} (cluster is ${vsan_status})"
        python3 -I "${VSAN_POWER}" restart "${cluster_id}" | while read -r line; do log "  ${line}"; done
        [[ "${PIPESTATUS[0]}" == "0" ]] || { log "  vSAN Restart Cluster failed - check vCenter"; exit 1; }
    else
        log "vSAN cluster is already powered on"
    fi
fi

govc about >/dev/null 2>&1 || { echo "Can't log in to ${GOVC_URL} - is vCenter up yet?"; exit 1; }

vms_matching() { govc find / -type m -name "$1" 2>/dev/null | grep -v '/vcf-services-runtime-template'; }
powered_off_vms() { govc find / -type m -name "$1" -runtime.powerState poweredOff 2>/dev/null | grep -v '/vcf-services-runtime-template'; }

check_ready() {
    local check=$1 pattern=$2
    case "${check}" in
        sddcm)
            curl -sk --max-time 10 -X POST "https://uk-bhr-p-sddcm-1.${DOMAIN}/v1/tokens" \
                -H 'Content-Type: application/json' \
                -d "{\"username\":\"${SDDC_MANAGER_USER}\",\"password\":\"${SDDC_MANAGER_PASSWORD}\"}" \
                | grep -q '"accessToken"' ;;
        nsx)
            curl -sk --max-time 10 -u "${NSX_USER}:${NSX_PASSWORD}" \
                "https://uk-bhr-p-nsx-1.${DOMAIN}/api/v1/cluster/status" \
                | python3 -I -c 'import sys,json; d=json.load(sys.stdin); sys.exit(0 if d["mgmt_cluster_status"]["status"]=="STABLE" else 1)' 2>/dev/null ;;
        http:*)
            local code
            code=$(curl -sk -o /dev/null --max-time 10 -w '%{http_code}' "https://${check#http:}.${DOMAIN}/")
            [[ "${code}" != "000" ]] && (( 10#${code} < 500 )) ;;
        tools)
            local vm
            while read -r vm; do
                [[ -z "${vm}" ]] && continue
                [[ "$(govc object.collect -s "${vm}" guest.toolsRunningStatus 2>/dev/null)" == "guestToolsRunning" ]] || return 1
            done <<< "$(vms_matching "${pattern}")" ;;
    esac
}

# Pre-checks: hosts connected and out of maintenance mode, vSAN restarted and healthy
log "Pre-checks"
for host in $(govc find "${CLUSTER}" -type h); do
    state=$(govc object.collect -s "${host}" runtime.connectionState)
    mm=$(govc object.collect -s "${host}" runtime.inMaintenanceMode)
    if [[ "${state}" != "connected" || "${mm}" == "true" ]]; then
        log "  ${host##*/}: ${state}, maintenance mode ${mm} - fix that first (did vSAN Restart Cluster finish?)"
        exit 1
    fi
done
disks=0
for host in $(govc find "${CLUSTER}" -type h); do
    n=$(govc host.esxcli -host "${host}" vsan storagepool list 2>/dev/null | grep -c 'Device:')
    log "  ${host##*/}: ${n} vSAN disks"
    disks=$((disks + n))
done
if (( disks != EXPECTED_VSAN_DISKS )); then
    log "  only ${disks}/${EXPECTED_VSAN_DISKS} vSAN disks - if ntnx-3 shows 0, its SAS3008 hung: power it fully off and on (IPMI)"
    exit 1
fi
first_host=$(govc find "${CLUSTER}" -type h | head -1)
inaccessible=$(govc host.esxcli -host "${first_host}" vsan debug object health summary get 2>/dev/null \
    | awk '$1 == "inaccessible" {print $2}')
if [[ "${inaccessible}" != "0" ]]; then
    log "  vSAN reports '${inaccessible:-unknown}' inaccessible objects - run Cluster -> vSAN -> Restart Cluster and wait for it"
    exit 1
fi
log "  hosts connected, ${disks} vSAN disks, 0 inaccessible objects"

log "Startup plan:"
for layer in "${LAYERS[@]}"; do
    IFS='|' read -r name pattern check timeout <<< "${layer}"
    all=$(vms_matching "${pattern}" | xargs -n1 basename 2>/dev/null | xargs)
    off=$(powered_off_vms "${pattern}" | xargs -n1 basename 2>/dev/null | xargs)
    if [[ -z "${all}" ]]; then
        printf "  %-38s %s\n" "${name}" "(no VMs - skipped)"
    else
        printf "  %-38s %s\n" "${name}" "${all}${off:+  [to power on: ${off}]}"
    fi
done
# VMs no layer covers (vCenter aside): this script won't start them, and the
# shutdown script refuses to run while they're on, so add them to LAYERS.
managed=""
for layer in "${LAYERS[@]}"; do
    IFS='|' read -r name pattern check timeout <<< "${layer}"
    managed+="$(vms_matching "${pattern}")"$'\n'
done
unmanaged=$(vms_matching "*" | grep -v '/uk-bhr-p-vc-2$' | grep -vxF -f <(echo "${managed}" | grep .) \
    | xargs -n1 basename 2>/dev/null | xargs)
[[ -n "${unmanaged}" ]] && printf "  %-38s %s\n" "Not in any layer (not started)" "${unmanaged}"

if ${DRY_RUN}; then
    log "Dry run - nothing changed"
    exit 0
fi

if ! ${ASSUME_YES}; then
    read -r -p "Power on and wait for each layer in this order? [y/N] " answer
    [[ "${answer}" =~ ^[Yy]$ ]] || { echo "Aborted"; exit 1; }
fi

for layer in "${LAYERS[@]}"; do
    IFS='|' read -r name pattern check timeout <<< "${layer}"
    [[ -z "$(vms_matching "${pattern}")" ]] && continue

    off=$(powered_off_vms "${pattern}")
    if [[ -n "${off}" ]]; then
        log "Powering on ${name}: $(echo "${off}" | xargs -n1 basename | xargs)"
        while read -r vm; do
            govc vm.power -on "${vm}" >/dev/null || { log "  failed to power on ${vm##*/}"; exit 1; }
        done <<< "${off}"
    else
        log "${name} is already powered on"
    fi

    log "  waiting for ${name} to be ready (${check}, up to ${timeout}s)"
    waited=0
    until check_ready "${check}" "${pattern}"; do
        if (( waited >= timeout )); then
            log "  ${name} not ready after ${timeout}s - check it, then re-run this script (it skips what's already on)"
            exit 1
        fi
        sleep 20
        waited=$((waited + 20))
    done
    log "  ${name} is ready (${waited}s), settling ${SETTLE_SECONDS}s"
    sleep "${SETTLE_SECONDS}"
done

log "All VCF appliances are powered on and answering."
cat <<EOF

Still worth checking by hand:
  - VCF Operations: https://uk-bhr-p-vcfops-1.${DOMAIN}/admin shows the cluster Online
    (if not: Bring Online), and the cloud proxy shows as connected.
  - VCF Automation can take another 15-30 min after its endpoint answers
    before https://uk-bhr-p-vcfa-1.${DOMAIN} logs in.
  - SDDC Manager dashboard and NSX (System -> Fabric -> Hosts) show no errors.
EOF

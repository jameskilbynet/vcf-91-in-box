#!/bin/bash
# Graceful shutdown of the NTNX1 VCF 9.1.1 management domain (steps 1-8).
# Guest-shuts-down the VCF VMs top-down through uk-bhr-p-vc-2, waiting for each
# layer to power off before starting the next. It stops before vCenter/vSAN:
# finish with the vSAN "Shutdown Cluster" wizard (printed at the end), which
# powers off vCenter and the three hosts safely. With --vsan the script runs
# that step itself through the vSAN API (vsan_cluster_power.py) and waits for
# the hosts to go down.
#
#   ./shutdown_ntnx1_vcf.sh --dry-run    # show what would be shut down, change nothing
#   ./shutdown_ntnx1_vcf.sh              # asks for confirmation first
#   ./shutdown_ntnx1_vcf.sh --yes        # no prompt
#   ./shutdown_ntnx1_vcf.sh --yes --vsan # ...and then vSAN Shutdown Cluster
#
# Startup is the reverse; see the README.

export GOVC_URL="${GOVC_URL:-uk-bhr-p-vc-2.jameskilby.cloud}"
export GOVC_USERNAME="${GOVC_USERNAME:-administrator@vsphere.local}"
export GOVC_PASSWORD="${GOVC_PASSWORD:-VMware123!VMware123!}"
export GOVC_INSECURE=1

CLUSTER="/ntnx1-dc/host/ntnx1-mgmt-cl01"
VCENTER_VM="uk-bhr-p-vc-2"
VCF_OPS_ADMIN_URL="https://uk-bhr-p-vcfops-1.jameskilby.cloud/admin"

# Shutdown order, top of the stack first. Each layer is a name pattern
# (govc find -name glob); a layer with no matching powered-on VMs is skipped.
LAYERS=(
    "VCF Automation|uk-bhr-p-vcf-asr-1-*"
    "VCF Operations cloud proxy|uk-bhr-p-vcf-proxy-1"
    "VCF Operations|uk-bhr-p-vcfops-1"
    "VCF management services runtime|uk-bhr-p-vcf-msr-1-*"
    "VCF License Server|uk-bhr-p-vcf-lic-1"
    "NSX Edges|uk-bhr-p-edge-1*"
    "NSX Manager|uk-bhr-p-nsx-1*"
    "SDDC Manager|uk-bhr-p-sddcm-1"
)

GUEST_SHUTDOWN_TIMEOUT=900   # seconds per layer before giving up
HOSTS_DOWN_TIMEOUT=1800      # --vsan: seconds to wait for the hosts to power off
FORCE_AFTER_TIMEOUT=false    # true = hard power off VMs that ignore the guest shutdown

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
VSAN_POWER="$(cd "$(dirname "$0")" && pwd)/vsan_cluster_power.py"

command -v govc >/dev/null || { echo "govc not found (brew install govc)"; exit 1; }
govc about >/dev/null 2>&1 || { echo "Can't log in to ${GOVC_URL} as ${GOVC_USERNAME}"; exit 1; }

powered_on_vms() {
    govc find / -type m -name "$1" -runtime.powerState poweredOn 2>/dev/null | grep -v "/${VCENTER_VM}$"
}

# Pre-checks: vSAN must not be resyncing, and every host must be connected
log "Pre-checks"

for host in $(govc find "${CLUSTER}" -type h); do
    state=$(govc object.collect -s "${host}" runtime.connectionState)
    if [[ "${state}" != "connected" ]]; then
        log "  ${host##*/} is ${state} - fix that before shutting down"
        exit 1
    fi
done
first_host=$(govc find "${CLUSTER}" -type h | head -1)
resync_bytes=$(govc host.esxcli -host "${first_host}" vsan debug resync summary get 2>/dev/null \
    | awk -F: '/TotalBytesLeftToResync/ {gsub(/ /, "", $2); print $2}')
inaccessible=$(govc host.esxcli -host "${first_host}" vsan debug object health summary get 2>/dev/null \
    | awk '$1 == "inaccessible" {print $2}')
if [[ -z "${resync_bytes}" || -z "${inaccessible}" ]]; then
    log "  couldn't read the vSAN resync/object health from ${first_host##*/} - check Monitor > vSAN by hand"
    exit 1
fi
if [[ "${resync_bytes}" != "0" ]]; then
    log "  vSAN is still resyncing (${resync_bytes} bytes left) - wait for it to finish"
    exit 1
fi
if [[ "${inaccessible}" != "0" ]]; then
    log "  ${inaccessible} vSAN objects are inaccessible - fix that before shutting down"
    exit 1
fi
log "  hosts connected, vSAN resync 0 bytes, 0 inaccessible objects"

# Plan
log "Shutdown plan:"
for layer in "${LAYERS[@]}"; do
    name="${layer%%|*}"; pattern="${layer#*|}"
    vms=$(powered_on_vms "${pattern}" | xargs -n1 basename 2>/dev/null | xargs)
    printf "  %-34s %s\n" "${name}" "${vms:-(none powered on - skipped)}"
done
if ${VSAN}; then
    cluster_id=$(govc find -i -maxdepth 0 "${CLUSTER}")
    vsan_status=$(python3 -I "${VSAN_POWER}" status "${cluster_id}") \
        || { log "  can't read the vSAN cluster power state: ${vsan_status}"; exit 1; }
    printf "  %-34s %s\n" "vCenter + vSAN + hosts" "vSAN Shutdown Cluster via the API (now ${vsan_status})"
else
    printf "  %-34s %s\n" "vCenter + vSAN + hosts" "vSAN Shutdown Cluster wizard (manual, see below)"
fi

if ${DRY_RUN}; then
    log "Dry run - nothing changed"
    exit 0
fi

if ! ${ASSUME_YES}; then
    echo
    echo "Take VCF Operations offline first if you want the cleanest shutdown:"
    echo "  ${VCF_OPS_ADMIN_URL} -> Take Offline"
    read -r -p "Shut down the VMs above in this order? [y/N] " answer
    [[ "${answer}" =~ ^[Yy]$ ]] || { echo "Aborted"; exit 1; }
fi

for layer in "${LAYERS[@]}"; do
    name="${layer%%|*}"; pattern="${layer#*|}"
    vms=$(powered_on_vms "${pattern}")
    [[ -z "${vms}" ]] && continue

    log "Shutting down ${name}: $(echo "${vms}" | xargs -n1 basename | xargs)"
    while read -r vm; do
        # Guest shutdown needs VMware Tools; fall back to a hard power off only if allowed
        if ! govc vm.power -s "${vm}" >/dev/null 2>&1; then
            log "  guest shutdown of ${vm##*/} failed (VMware Tools not running?)"
            if ${FORCE_AFTER_TIMEOUT}; then
                govc vm.power -off -force "${vm}" >/dev/null && log "  powered off ${vm##*/}"
            else
                log "  stopping - shut ${vm##*/} down by hand, then re-run this script"
                exit 1
            fi
        fi
    done <<< "${vms}"

    waited=0
    while [[ -n "$(powered_on_vms "${pattern}")" ]]; do
        if (( waited >= GUEST_SHUTDOWN_TIMEOUT )); then
            remaining=$(powered_on_vms "${pattern}" | xargs -n1 basename | xargs)
            if ${FORCE_AFTER_TIMEOUT}; then
                log "  timed out - forcing power off: ${remaining}"
                powered_on_vms "${pattern}" | while read -r vm; do govc vm.power -off -force "${vm}" >/dev/null; done
            else
                log "  timed out after ${GUEST_SHUTDOWN_TIMEOUT}s waiting for: ${remaining}"
                log "  stopping - check their consoles, then re-run this script (it skips what's already off)"
                exit 1
            fi
        fi
        sleep 10
        waited=$((waited + 10))
    done
    log "  ${name} is off (${waited}s)"
done

log "All VCF VMs are off. Only ${VCENTER_VM} is still running."

if ${VSAN}; then
    # Host names now, while vCenter is still up, to watch them power off.
    hosts=$(govc find "${CLUSTER}" -type h | xargs -n1 basename)
    log "vSAN Shutdown Cluster on ${CLUSTER##*/}"
    out=$(python3 -I "${VSAN_POWER}" shutdown "${cluster_id}")
    log "  ${out}"
    [[ "${out}" == OK* ]] || exit 1
    # vSAN powers off vCenter, then the hosts. Done once none answers HTTPS.
    waited=0
    while true; do
        up=""
        for h in ${hosts}; do
            [[ "$(curl -sk -o /dev/null --max-time 5 -w '%{http_code}' "https://${h}/")" != "000" ]] && up="${up} ${h}"
        done
        [[ -z "${up}" ]] && break
        if (( waited >= HOSTS_DOWN_TIMEOUT )); then
            log "  hosts still up after ${HOSTS_DOWN_TIMEOUT}s:${up} - check the ESXi consoles / IPMI"
            exit 1
        fi
        sleep 30
        waited=$((waited + 30))
    done
    log "vCenter and all hosts are down (${waited}s). The lab is off."
    echo
    echo "To start up again: power the hosts on (IPMI), then ./startup_ntnx1_vcf.sh --yes --vsan"
    echo "(it waits for vCenter, runs vSAN Restart Cluster, then starts the VMs)."
    exit 0
fi
cat <<EOF

Final step (manual): in https://${GOVC_URL}/ui
  right-click ntnx1-mgmt-cl01 -> vSAN -> Shutdown Cluster -> run the pre-checks -> Shutdown.
The wizard shuts down ${VCENTER_VM} last and powers off ntnx-1/2/3.
Don't shut down ${VCENTER_VM} yourself.

To start up again: power on the hosts (IPMI), wait for vCenter, then
Cluster -> vSAN -> Restart Cluster, and power the VMs on in the reverse order
of this script (SDDC Manager first, VCF Automation last).
EOF

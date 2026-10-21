#!/bin/bash
# Graceful shutdown of the NTNX1 VCF 9.1.1 management domain (steps 1-8).
# Guest-shuts-down the VCF VMs top-down through uk-bhr-p-vc-2, waiting for each
# layer to power off before starting the next. It stops before vCenter/vSAN:
# finish with the vSAN "Shutdown Cluster" wizard (printed at the end), which
# powers off vCenter and the three hosts safely.
#
#   ./shutdown_ntnx1_vcf.sh --dry-run    # show what would be shut down, change nothing
#   ./shutdown_ntnx1_vcf.sh              # asks for confirmation first
#   ./shutdown_ntnx1_vcf.sh --yes        # no prompt
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
FORCE_AFTER_TIMEOUT=false    # true = hard power off VMs that ignore the guest shutdown

### DO NOT EDIT BEYOND HERE ###

DRY_RUN=false
ASSUME_YES=false
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=true ;;
        --yes) ASSUME_YES=true ;;
        *) echo "Unknown option: $arg"; exit 1 ;;
    esac
done

log() { echo -e "[$(date +%H:%M:%S)] $*"; }

command -v govc >/dev/null || { echo "govc not found (brew install govc)"; exit 1; }
govc about >/dev/null 2>&1 || { echo "Can't log in to ${GOVC_URL} as ${GOVC_USERNAME}"; exit 1; }

powered_on_vms() {
    govc find / -type m -name "$1" -runtime.powerState poweredOn 2>/dev/null | grep -v "/${VCENTER_VM}$"
}

# Pre-checks: vSAN must not be resyncing, and every host must be connected
log "Pre-checks"
resync_bytes=0
for host in $(govc find "${CLUSTER}" -type h); do
    state=$(govc object.collect -s "${host}" runtime.connectionState)
    if [[ "${state}" != "connected" ]]; then
        log "  ${host##*/} is ${state} - fix that before shutting down"
        exit 1
    fi
done
first_host=$(govc find "${CLUSTER}" -type h | head -1)
resync_bytes=$(govc host.esxcli -host "${first_host}" vsan debug resync summary get 2>/dev/null \
    | awk -F: '/Total Bytes Left To Resync/ {gsub(/ /, "", $2); print $2}')
if [[ -n "${resync_bytes}" && "${resync_bytes}" != "0" ]]; then
    log "  vSAN is still resyncing (${resync_bytes} bytes left) - wait for it to finish"
    exit 1
fi
log "  hosts connected, vSAN resync: ${resync_bytes:-unknown (check Monitor > vSAN > Resyncing Objects)}"

# Plan
log "Shutdown plan:"
for layer in "${LAYERS[@]}"; do
    name="${layer%%|*}"; pattern="${layer#*|}"
    vms=$(powered_on_vms "${pattern}" | xargs -n1 basename 2>/dev/null | xargs)
    printf "  %-34s %s\n" "${name}" "${vms:-(none powered on - skipped)}"
done
printf "  %-34s %s\n" "vCenter + vSAN + hosts" "vSAN Shutdown Cluster wizard (manual, see below)"

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
cat <<EOF

Final step (manual): in https://${GOVC_URL}/ui
  right-click ntnx1-mgmt-cl01 -> vSAN -> Shutdown Cluster -> run the pre-checks -> Shutdown.
The wizard shuts down ${VCENTER_VM} last and powers off ntnx-1/2/3.
Don't shut down ${VCENTER_VM} yourself.

To start up again: power on the hosts (IPMI), wait for vCenter, then
Cluster -> vSAN -> Restart Cluster, and power the VMs on in the reverse order
of this script (SDDC Manager first, VCF Automation last).
EOF

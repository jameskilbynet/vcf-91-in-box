#!/bin/bash
# Author: William Lam
# NTNX1 fork: deploys with govc instead of ovftool. Log in to vCenter first
# (govc reuses the persisted session when GOVC_URL and GOVC_USERNAME match):
#   export GOVC_URL=uk-bhr-p-vc-1.jameskilby.cloud GOVC_USERNAME=administrator@vsphere.cloud GOVC_INSECURE=1
#   govc session.login -persist-session=true

# From the VIS offline depot. An http(s) source is downloaded to OVA_CACHE_DIR
# first: streaming it into govc fails part-way ("unexpected EOF" on disk2)
# because the depot is a plain HTTP/1.0 server. A local path is used as-is.
VCF_INSTALLER_OVA="${VCF_INSTALLER_OVA:-http://uk-bhr-p-vis-1.jameskilby.cloud:8081/PROD/COMP/SDDC_MANAGER_VCF/VCF-SDDC-Manager-Appliance-9.1.1.0200.25801071.ova}"
OVA_CACHE_DIR="${OVA_CACHE_DIR:-${TMPDIR:-/tmp}}"

# Deployed onto the Z840 (uk-bhr-p-esx-a) via vCenter, NOT onto an NTNX node:
# ESA claims every NTNX SSD and the SATADOM can't hold VMs, so an external
# installer deploys a fresh SDDC Manager (sddcManagerSpec.useExistingDeployment=false).
export GOVC_URL="${GOVC_URL:-uk-bhr-p-vc-1.jameskilby.cloud}"
export GOVC_USERNAME="${GOVC_USERNAME:-administrator@vsphere.cloud}"
export GOVC_INSECURE=1
VM_HOST="/uk-bhr-p-dc-1/host/GPU/uk-bhr-p-esx-a.jameskilby.cloud"
VM_POOL="/uk-bhr-p-dc-1/host/GPU/Resources"
VM_NETWORK="DSwitch-VCF-Mgmt"   # VLAN 100 DVPG on DSwitch (create first, see README)
VM_DATASTORE="Z840-NVMe1"

VCF_INSTALLER_VMNAME=uk-bhr-p-vcfi-1
VCF_INSTALLER_HOSTNAME=uk-bhr-p-vcfi-1.jameskilby.cloud
VCF_INSTALLER_IP=192.168.100.9
VCF_INSTALLER_SUBNET=255.255.255.0
VCF_INSTALLER_GATEWAY=192.168.100.1
VCF_INSTALLER_DNS_SERVER=192.168.10.250,192.168.10.251
VCF_INSTALLER_DNS_DOMAIN=jameskilby.cloud
VCF_INSTALLER_DNS_SEARCH=jameskilby.cloud
VCF_INSTALLER_NTP=192.168.100.1
VCF_INSTALLER_ROOT_PASSWORD="VMware123!VMware123!"
VCF_INSTALLER_ADMIN_PASSWORD="VMware123!VMware123!"

### DO NOT EDIT BEYOND HERE ###

set -e
command -v govc >/dev/null || { echo "govc not found (brew install govc)"; exit 1; }
govc about >/dev/null || { echo "govc can't reach ${GOVC_URL} - run: govc session.login -persist-session=true"; exit 1; }
if govc vm.info "${VCF_INSTALLER_VMNAME}" 2>/dev/null | grep -q "Name:"; then
    echo "VM ${VCF_INSTALLER_VMNAME} already exists"
    exit 1
fi

if [[ "${VCF_INSTALLER_OVA}" == http* ]]; then
    LOCAL_OVA="${OVA_CACHE_DIR%/}/$(basename "${VCF_INSTALLER_OVA}")"
    if [[ ! -s "${LOCAL_OVA}" ]]; then
        echo "Downloading ${VCF_INSTALLER_OVA} to ${LOCAL_OVA} ..."
        curl -fSL -o "${LOCAL_OVA}.part" "${VCF_INSTALLER_OVA}"
        mv "${LOCAL_OVA}.part" "${LOCAL_OVA}"
    fi
    VCF_INSTALLER_OVA="${LOCAL_OVA}"
fi
[[ -f "${VCF_INSTALLER_OVA}" ]] || { echo "VCF Installer OVA not found: ${VCF_INSTALLER_OVA}"; exit 1; }

OPTIONS=$(mktemp)
trap 'rm -f "${OPTIONS}"' EXIT
python3 -I - "${OPTIONS}" <<EOF
import json, sys
props = {
    "vami.hostname": "${VCF_INSTALLER_HOSTNAME}",
    "vami.ip_address_version.SDDC-Manager": "IPv4",
    "vami.ip0.SDDC-Manager": "${VCF_INSTALLER_IP}",
    "vami.netmask0.SDDC-Manager": "${VCF_INSTALLER_SUBNET}",
    "vami.gateway.SDDC-Manager": "${VCF_INSTALLER_GATEWAY}",
    "vami.domain.SDDC-Manager": "${VCF_INSTALLER_DNS_DOMAIN}",
    "vami.searchpath.SDDC-Manager": "${VCF_INSTALLER_DNS_SEARCH}",
    "vami.DNS.SDDC-Manager": "${VCF_INSTALLER_DNS_SERVER}",
    "ROOT_PASSWORD": "${VCF_INSTALLER_ROOT_PASSWORD}",
    "LOCAL_USER_PASSWORD": "${VCF_INSTALLER_ADMIN_PASSWORD}",
    "guestinfo.ntp": "${VCF_INSTALLER_NTP}",
}
json.dump({
    "Name": "${VCF_INSTALLER_VMNAME}",
    "DiskProvisioning": "thin",
    "IPAllocationPolicy": "fixedPolicy",
    "PowerOn": True,
    "InjectOvfEnv": True,
    "WaitForIP": False,
    "NetworkMapping": [{"Name": "Network 1", "Network": "${VM_NETWORK}"}],
    "PropertyMapping": [{"Key": k, "Value": v} for k, v in props.items()],
}, open(sys.argv[1], "w"))
EOF

echo -e "\nDeploying VCF Installer ${VCF_INSTALLER_VMNAME} to ${VM_HOST} (${VM_DATASTORE}) ..."
govc import.ova -host="${VM_HOST}" -pool="${VM_POOL}" -ds="${VM_DATASTORE}" -options="${OPTIONS}" "${VCF_INSTALLER_OVA}"

echo "Waiting for https://${VCF_INSTALLER_HOSTNAME} ..."
for i in $(seq 1 60); do
    if curl -sk -o /dev/null --max-time 5 "https://${VCF_INSTALLER_IP}/"; then
        echo "VCF Installer is up: https://${VCF_INSTALLER_HOSTNAME}"
        exit 0
    fi
    sleep 20
done
echo "Timed out waiting for the VCF Installer UI - check the VM console"
exit 1

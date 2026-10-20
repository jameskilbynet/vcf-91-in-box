#!/bin/bash
# Author: William Lam

OVFTOOL="/Applications/VMware OVF Tool/ovftool"
# Streamed straight from the VIS offline depot (ovftool accepts an HTTP source)
VCF_INSTALLER_OVA="http://uk-bhr-p-vis-1.jameskilby.cloud:8081/PROD/COMP/SDDC_MANAGER_VCF/VCF-SDDC-Manager-Appliance-9.1.1.0200.25801071.ova"

# Check if ovftool exists and is executable
if [[ ! -x "$OVFTOOL" ]]; then
    echo "ovftool not found or is not executable: $OVFTOOL"
    exit 1
fi

# Check if the OVA file exists
if [[ "$VCF_INSTALLER_OVA" != http* && ! -f "$VCF_INSTALLER_OVA" ]]; then
    echo "VCF Installer OVA not found: $VCF_INSTALLER_OVA"
    exit 1
fi

# Deployed onto the Z840 (uk-bhr-p-esx-a) via vCenter, NOT onto an NTNX node:
# the NTNX SATADOMs are too small for a local datastore, and an external
# installer deploys a fresh SDDC Manager (sddcManagerSpec.useExistingDeployment=false).
VCENTER="uk-bhr-p-vc-1.jameskilby.cloud"
VCENTER_TARGET="uk-bhr-p-dc-1/host/GPU/uk-bhr-p-esx-a.jameskilby.cloud"
VCENTER_USERNAME="administrator%40vsphere.cloud"   # URL-encoded; ovftool prompts for the password
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

echo -e "\nDeploying VCF Installer ${VCF_INSTALLER_VMNAME} ..."
"${OVFTOOL}" --acceptAllEulas --noSSLVerify --skipManifestCheck --X:injectOvfEnv --allowExtraConfig --X:waitForIp --sourceType=OVA --powerOn \
"--net:Network 1=${VM_NETWORK}" --datastore=${VM_DATASTORE} --diskMode=thin --name=${VCF_INSTALLER_VMNAME} \
"--prop:vami.hostname=${VCF_INSTALLER_HOSTNAME}" \
"--prop:vami.ip0.SDDC-Manager=${VCF_INSTALLER_IP}" \
"--prop:vami.netmask0.SDDC-Manager=${VCF_INSTALLER_SUBNET}" \
"--prop:vami.gateway.SDDC-Manager=${VCF_INSTALLER_GATEWAY}" \
"--prop:vami.domain.SDDC-Manager=${VCF_INSTALLER_DNS_DOMAIN}" \
"--prop:vami.searchpath.SDDC-Manager=${VCF_INSTALLER_DNS_SEARCH}" \
"--prop:vami.DNS.SDDC-Manager=${VCF_INSTALLER_DNS_SERVER}" \
"--prop:ROOT_PASSWORD=${VCF_INSTALLER_ROOT_PASSWORD}" \
"--prop:LOCAL_USER_PASSWORD=${VCF_INSTALLER_ADMIN_PASSWORD}" \
"--prop:guestinfo.ntp=${VCF_INSTALLER_NTP}" \
"${VCF_INSTALLER_OVA}" "vi://${VCENTER_USERNAME}@${VCENTER}/${VCENTER_TARGET}"

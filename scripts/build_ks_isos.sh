#!/bin/bash
# Builds one bootable ESX ISO per NTNX node with its kickstart baked in, for
# mounting over IPMI virtual media (the Nutanix nodes have no USB stick).
# Requires: brew install xorriso
set -euo pipefail

ESX_ISO="${1:-${HOME}/Github/VMware-VMvisor-Installer-9.1.1.0100.25782009.x86_64.iso}"
CONFIG_DIR="$(cd "$(dirname "$0")/../config" && pwd)"
OUT_DIR="${2:-${PWD}/iso}"

command -v xorriso >/dev/null || { echo "xorriso not found (brew install xorriso)"; exit 1; }
[[ -f "$ESX_ISO" ]] || { echo "ESX ISO not found: $ESX_ISO"; exit 1; }
mkdir -p "$OUT_DIR"

for n in 01 02 03; do
    work="$(mktemp -d)"
    xorriso -osirrox on -indev "$ESX_ISO" -extract / "$work" >/dev/null 2>&1
    chmod -R u+w "$work"
    cp "${CONFIG_DIR}/KS-ESX${n}.CFG" "$work/KS-ESX${n}.CFG"
    # allowLegacyCPU=true: Xeon E5-2640 v3 (Haswell) is discontinued in ESX 9.x
    for cfg in "$work/BOOT.CFG" "$work/EFI/BOOT/BOOT.CFG"; do
        sed -i '' -e "s|^kernelopt=.*|kernelopt=runweasel cdromBoot ks=cdrom:/KS-ESX${n}.CFG allowLegacyCPU=true|" "$cfg"
    done
    xorriso -as mkisofs -relaxed-filenames -J -R -V "ESX-KS-${n}" \
        -o "${OUT_DIR}/ESX-NTNX-${n}.iso" \
        -b ISOLINUX.BIN -c BOOT.CAT -no-emul-boot -boot-load-size 4 -boot-info-table \
        -eltorito-alt-boot -e EFIBOOT.IMG -no-emul-boot "$work" >/dev/null 2>&1
    rm -rf "$work"
    echo "Built ${OUT_DIR}/ESX-NTNX-${n}.iso (KS-ESX${n}.CFG)"
done

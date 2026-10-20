# VMware Cloud Foundation (VCF) 9.1.1 in a Box

Fork of [lamw/vcf-91-in-box](https://github.com/lamw/vcf-91-in-box), adapted for the 3-node NTNX1 cluster (see [NTNX1 fork](#ntnx1-fork-this-branch)). Upstream: deploy a fully functional VMware Cloud Foundation 9.1.1 environment on one, two or three physical ESX hosts, optimized for development and lab use. This setup enables users to explore the full capabilities of VCF 9.1.1, ranging from Fleet Management, Self-Service Automation with Multi-Tenancy to running modern container and AI workloads, all while using minimal compute and storage resources.

📒 This deployment does not use Nested ESX and instead runs directly on physical hosts, in contrast to the [VCF Holodeck](https://vmware.github.io/Holodeck/) solution.

![](screenshots/screenshot-0.png)

## Table of Contents

* [Changelog](#changelog)
* [Bill of Materials (BOM)](#bill-of-materials-bom)
* [NTNX1 fork](#ntnx1-fork-this-branch)
* [Post Installation](#post-installation)
* [Additional Blog Resources](#additional-blog-resources)

## Changelog

* **10/23/2026**
  * Updated for VCF 9.1.1

* **05/28/2026**
  * Initial Release

## Bill of Materials (BOM)

![](screenshots/screenshot-18.jpg)

| Category | Component | Function / Details | Qty | Unit Price (USD) |
| :--- | :--- | :--- | :---: | :---: |
| Server | [Minisforum MS-A2 (7945HX) Barebones](amzn.to/46xuK3X) | ESX Host | 2-3 | $789.00 |
| Server | [Crucial 128GB Kit (2x64GB) DDR5 SODIMM](amzn.to/4bcpXFJ) | ESX Memory | 2-3 | $279.99 USD ($1195 USD as of 01/07/26) |
| Server | [SK Hynix Gold P31 500GB NVME](amzn.to/4eKEQkm) | ESX Install + VMFS Volume | 2-3 | $44.09 USD |
| Server | [Samsung SSD 990 PRO 1TB NVME](https://amzn.to/4rp0uku) | vSAN ESA | 2-3 | $399 |
| Server | [Samsung 980 PRO 1TB NVME](https://amzn.to/4hcoDGc) | NVMe Tierinng | 2-3 | Owned Previously |
| Networking | [MikroTik CRS304-4XG-IN](amzn.to/44J1rt4) | 10GbE Routing Switch | 1 | $188.00 |
| Networking | [Sodola 5 x 10GbE Managed Switch](amzn.to/3PD5eUY) | 10GbE Managed Switch | 1 | $169.00 |
| Networking | [10Gtek SFP+ to RJ45 Module](https://amzn.to/4nAs6B9) | SFP+ to RJ45 Adapter for MS-A2 | 2-3 | $70.75 |
| Private AI | [RTX 4000 SFF Ada with 20GB VRAM](https://amzn.to/4mSxQ7J) | GPU for Private AI Services | 1 | $1,199 |
| Private AI | [Aoostar AG01 OCuLink eGPU Dock](https://aoostar.com/products/aoostar-ag01-egpu-dock-with-oculink-port-built-in-huntkey-800w-power-supply-pre-order-itll-be-shipped-around-february-20th) | eGPU Dock | 1 | $179 |
| Rack Enclosure | [DeskPi RackMate T2 (12U)](https://amzn.to/4mZmlvd) | Mini-Rack Chassis (12U) | 1 | $159.99 |
| Rack Accessory | [DeskPi 7.84 inch LCD Touch Screen](https://amzn.to/3KCZ0C4) | 2U Direct Console Display | 1 | $89.99 |
| Rack Accessory | [DeskPi Server 2-Pack Rack Shelf](https://amzn.to/46SFjgU) | 0.5U Mounting Shelf | 1 | $32.39 |
| Rack Accessory | [DeskPi Server Rack Shelf](https://amzn.to/3KD7Orz) | 1U Mounting Shelf | 2 | $25.99 |
| Rack Accessory | [DeskPi Server Rack Blank Panel](https://amzn.to/4nL5xsV) | 2U Blank Panel | 1 | $14.99 |
| Rack Accessory | [DeskPi 12-port Patch Panel](https://amzn.to/42vwfNP) | 0.5U Ethernet Patch Panel | 1 | $18.39 |
| Rack Accessory | [DeskPi 12-Port Blank Patch Panel](https://amzn.to/48jOAB9) | 0.5U Blank Patch Panel | 1 | $10.39 |
| Rack Accessory | [Blazin3D 12-port PDU](https://amzn.to/4n4EUhG) | 1U Power Distribution Unit | 1 | $49.99 |
| Rack Accessory | [1.5 Inch EMA 5-15P Extension Power Cord](https://amzn.to/4gZg413) | Power Cables | 3 | $6.99 |
| Rack Accessory | [Dual 120MM USB Fan]((https://amzn.to/3W03iFV)) | Rack Enclosure Cooling | 1 | $21.99 |
| Rack Accessory | [Monoprice SlimRun 5-pack 2 feet Cat6 Cable](https://amzn.to/3IYcCXT) | Patch Cabling | 1 | $9.02 |
| Rack Accessory | [Monoprice SlimRun 5-pack 6 inch Cat6 Cable](https://amzn.to/4gZS6CV) | Short Patch Cabling | 1 | $9.02 |
| Rack Accessory | [D-Ring Cable Management Hooks](https://amzn.to/4o3Etpb) | 5-Pack Routing Hooks | 1 | $13.79 |
| Rack Accessory | [18" Zip Ties](https://amzn.to/4q55Y2T) | 100-Pack Cable Ties | 1 | $9.99 |

📒 The above BOM is just an example. You can certainly swap out full systems and/or components that you might already have or prefer alternatives. Just know that you are responsible for adjusting any configuration that may differ from the referenced BOM.

## NTNX1 fork (this branch)

This branch adapts William Lam's VCF 9.1.1 in a Box to the three **Nutanix NX (G4/G5)** nodes in the NTNX1 cluster:
`uk-bhr-p-ntnx-1/2/3`, each with 2× Xeon E5-2640 v3, 256 GB RAM, a 64 GB SATADOM, 960 GB SATA SSDs on an LSI SAS3008, 2× 1GbE (igbn, unused) and 2× 25GbE (i40en vmnic2/3 → mikrotik-sw-1).
Like upstream, it is **bare metal**: it reinstalls ESX on the nodes. It is not nested, so it's not Holodeck.

What changed vs upstream:

| Area | Upstream (MS-A2) | NTNX1 |
|---|---|---|
| Boot / install | USB stick, `ks=usb:` | Per-host ISO over IPMI virtual media, `ks=cdrom:` + `allowLegacyCPU=true` ([scripts/build_ks_isos.sh](scripts/build_ks_isos.sh)) |
| Install disk | NVMe | 64 GB SATADOM, `--ignoreprereqwarnings` |
| vSAN | ESA + HCL-bypass flags | **OSA**: Samsung MZ7KM960 = cache, HPE VK0960 = capacity (tagged `capacityFlash` in kickstart); ESA flags removed |
| NICs | vmnic1, one uplink | vmnic2 + vmnic3, both active |
| VLANs | 30/40/50/60/70 | 100 mgmt, 101 vMotion, 102 vSAN, 103 host TEP, 106 DTGW external (already live on mikrotik-sw-1, gateways `.1`, SVI MTU 9212) |
| Mgmt MTU | vSwitch0 + vmk0 at 9000 | vSwitch0 9000 (for the jumbo vmkping validation), vmk0 1500 (the VLAN 100 SVI is 1500) |
| AMD / NVMe-tiering tweaks | yes | removed (Intel, no NVMe); LRO/TSO-off kept for i40en |
| VCF Installer | on esx01, reused as SDDC Manager | on **uk-bhr-p-esx-a** (Z840-NVMe1) via vCenter, OVA streamed from the VIS depot; deploys a **new** SDDC Manager (`useExistingDeployment: false`) |
| Depot | python http :8888 | VIS appliance `http://uk-bhr-p-vis-1.jameskilby.cloud:8081` |
| Installer overrides | single-host + ESA disk claim | longer NSX/VSP timeouts + retries; also fixes an upstream bug where OperationsManager overrides were written to the DomainManager file |
| Deployment JSON | 6 samples | [config/three-node-vsan-osa-tep-ntnx1.json](config/three-node-vsan-osa-tep-ntnx1.json) only |

### ⚠️ Read before starting

* **This is destructive.** It reinstalls ESX on the three SATADOMs and wipes the SSDs. On ntnx-1 that includes `NTNX1-Local` and `NTNX1-Local-Samsung` (≈6 GB used, so check what's on them first). It also ends Holodeck on NTNX1. The VIS depot and HoloRouter are now on esx-a, so they aren't touched.
* **The CPU is unsupported.** Broadcom discontinued Broadwell-EP in VCF 9.x, and Haswell-EP is older still. `allowLegacyCPU=true` turns the installer's hard stop into a warning; Haswell has the XSAVE instruction ESX requires. Expect future vLCM upgrades to need the same workaround, or to refuse.
* **The vSAN hardware is off the HCL.** SATA SSDs on an LSI SAS3008 aren't on it, which is why this uses OSA rather than ESA (ESA also misbehaved on these nodes). Acknowledge any HCL warnings during validation.
* **ntnx-3 only shows 2 SSDs** (it had 3 in September). Raw capacity is 2+2+1 = 5 × 960 GB of capacity tier, about 2.2 TB usable at FTT=1, unevenly spread. Re-seat or replace the missing drive and add it to `KS-ESX03.CFG` first, if you can.
* The VIS depot returned a `404` for `VCF_SALT_RAAS` 9.1.1.0100 during the Holodeck run. Watch for it at the binary-download step.

### Prerequisites

1. **Remove the three hosts from `uk-bhr-p-vc-1`.** They're in maintenance mode and not responding, so use *Remove from Inventory*.
2. **Create a VLAN 100 port group on DSwitch** for the installer VM on esx-a. Upstream calls it `DSwitch-VCF-Mgmt`: VLAN 100, default security. esx-a's switch ports already carry VLAN 100 (the `hosts` group on mikrotik-sw-1).
3. **Create the DNS records** in AD (`jameskilby.cloud`, forward **and** reverse). Create the reverse zone `100.168.192.in-addr.arpa` if it's missing. The ntnx A/PTR records currently point at 192.168.38.24–26 and must be **replaced**. Check that none of the new names already exist.

| Hostname (`.jameskilby.cloud`) | IP | Function |
|---|---|---|
| uk-bhr-p-vcfi-1 | 192.168.100.9 | VCF Installer (temporary, on esx-a) |
| uk-bhr-p-ntnx-1 / -2 / -3 | 192.168.100.11 / .12 / .13 | ESX hosts |
| uk-bhr-p-sddcm-1 | 192.168.100.18 | SDDC Manager |
| uk-bhr-p-vc-2 | 192.168.100.19 | Management vCenter (SSO `vsphere.local`) |
| uk-bhr-p-vcfops-1 | 192.168.100.20 | VCF Operations |
| uk-bhr-p-vcf-msr-1 | 192.168.100.21 | Management Services Runtime |
| uk-bhr-p-vcf-flt-1 | 192.168.100.22 | Fleet components |
| uk-bhr-p-vcf-int-1 | 192.168.100.23 | Instance components |
| uk-bhr-p-vcf-lic-1 | 192.168.100.24 | License Server |
| uk-bhr-p-vcf-idb-1 | 192.168.100.27 | Identity Broker |
| — | 192.168.100.33–46 | MSR node pool |
| uk-bhr-p-nsx-1 | 192.168.100.48 | NSX VIP |
| uk-bhr-p-nsx-1a | 192.168.100.49 | NSX Manager |
| uk-bhr-p-vcf-proxy-1 | 192.168.100.55 | Ops cloud proxy |
| uk-bhr-p-vcf-asr-1 | 192.168.100.56 | Automation Services Runtime |
| uk-bhr-p-vcfa-1 | 192.168.100.57 | VCF Automation |
| — | 192.168.100.65–70 | Automation node pool |

Host vmkernel pools: vMotion `192.168.101.11-20`, vSAN `192.168.102.11-20`, TEP `192.168.103.11-30`. DTGW: VLAN 106, gateway `192.168.106.1/24`, external block `192.168.106.128/26`.

4. **Pre-flight from something on VLAN 100** (e.g. the installer VM once it's up):
   * DNS really reaches AD: `dig @1.2.3.4 uk-bhr-p-vc-2.jameskilby.cloud` must *fail*. If it answers, port 53 is being hijacked the same way it is on VLAN 4.
   * NTP: `ntpdate -q 192.168.100.1` (mikrotik-sw-1 is the lab NTP server).
   * Depot: `curl -sI http://uk-bhr-p-vis-1.jameskilby.cloud:8081/PROD/metadata/productVersionCatalog/v1/productVersionCatalog.json` returns 200.
5. Tools on the Mac: `brew install xorriso`, plus [OVFTool](https://developer.broadcom.com/tools/open-virtualization-format-ovf-tool/latest) and PowerCLI.

### Installation

1. Build the per-host ISOs (default input: `~/Github/VMware-VMvisor-Installer-9.1.1.0100.25782009.x86_64.iso`):
   ```bash
   ./scripts/build_ks_isos.sh            # -> ./iso/ESX-NTNX-0{1,2,3}.iso
   ```
2. Mount `ESX-NTNX-0N.iso` on node N through its IPMI virtual media and boot from the virtual CD. The install is unattended and reboots twice. The host should come up at `https://uk-bhr-p-ntnx-N.jameskilby.cloud`, with vSAN disks showing as eligible (`vdq -q`) and the HPE disks flagged `IsCapacityFlash: 1`.
3. Deploy the VCF Installer onto esx-a. It prompts for the vCenter password:
   ```bash
   ./scripts/deploy_vcf_installer.sh
   ```
4. Configure the installer (depot, override properties, service restart):
   ```powershell
   $env:VCENTER_PASSWORD = '...'; ./scripts/setup_vcf_installer.ps1
   ```
5. Open `https://uk-bhr-p-vcfi-1.jameskilby.cloud/` → *Depot settings and binary management* → download every binary until each one shows Success.
6. *Deploy using JSON spec* → upload [config/three-node-vsan-osa-tep-ntnx1.json](config/three-node-vsan-osa-tep-ntnx1.json). All passwords are `VMware123!VMware123!` (ESX root `VMware123!`), so change them in the JSON, the kickstarts and the scripts before using this for anything that isn't a lab. Acknowledge the CPU/HCL warnings, then deploy. Expect it to take several hours on this hardware.
7. Afterwards, power off and delete `uk-bhr-p-vcfi-1` and its DNS record. Optionally, add `esx-iscsi01` as supplemental storage: put the new host IQNs into TrueNAS initiator group 4 and rebuild vmk3/vmk4 (60.x/61.x) on the new VDS.

## Post Installation

![](screenshots/screenshot-15.png)

There are a number of [post-VCF deployment optimizations](https://williamlam.com/2026/04/automating-lab-optimizations-for-post-deployment-of-vmware-cloud-foundation-vcf.html) that should be run for lab environments. You can refer to the linked blog post and run the PowerShell script `vcf-post-deploy-lab-tweaks.ps1`.

![](screenshots/screenshot-16.png)

## Additional Blog Resources

* [VMware Cloud Foundation (VCF) on Minisforum MS-A2](https://williamlam.com/2025/06/vmware-cloud-foundation-vcf-on-minisforum-ms-a2.html)
   * [VCF 9.x Hardware BOM for Silicon Valley VMUG](https://williamlam.com/2025/07/vcf-9-0-hardware-bom-for-silicon-valley-vmug.html)
   * [My VCF 9 Lab Mini-Rack](https://williamlam.com/2025/10/my-vcf-9-lab-mini-rack.html)
* [VCF 9.1 Resources](https://williamlam.com/vmware-cloud-foundation-9)
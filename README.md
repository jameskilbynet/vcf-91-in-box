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
| vSAN | ESA + HCL-bypass flags | ESA + the same HCL-bypass flags; kickstart wipes every local SSD so SDDC Manager can claim them |
| NICs | vmnic1, one uplink | vmnic2 + vmnic3, both active |
| VLANs | 30/40/50/60/70 | All of sw-1's VCF VLANs (live on the ntnx ports, gateways `.1`, SVI MTU 9212 on 101–104): 100 mgmt, 101 vMotion, 102 vSAN, 103 host TEP, 104 Edge TEP, 105 VM-Network, 106/107 Tier-0 uplinks |
| North-south | Distributed Transit Gateway (VLAN 70) | **Centralized** connectivity: a 2-node NSX Edge cluster + Tier-0 (eBGP AS 65100 ↔ sw-1 AS 65000), created on Day 2 — the 9.1 installer can't deploy Edges at bring-up |
| Mgmt MTU | vSwitch0 + vmk0 at 9000 | vSwitch0 9000 (for the jumbo vmkping validation), vmk0 1500 (the VLAN 100 SVI is 1500) |
| AMD / NVMe-tiering tweaks | yes | removed (Intel, no NVMe); LRO/TSO-off kept for i40en |
| VCF Installer | on esx01, reused as SDDC Manager | on **uk-bhr-p-esx-a** (Z840-NVMe1) via vCenter, OVA streamed from the VIS depot; deploys a **new** SDDC Manager (`useExistingDeployment: false`) |
| Depot | python http :8888 | VIS appliance `http://uk-bhr-p-vis-1.jameskilby.cloud:8081` |
| Installer overrides | single-host + ESA disk claim | ESA disk claim (no single-host flag) + longer NSX/VSP timeouts + retries; also fixes an upstream bug where OperationsManager overrides were written to the DomainManager file |
| Deployment JSON | 6 samples | [config/three-node-vsan-esa-tep-ntnx1.json](config/three-node-vsan-esa-tep-ntnx1.json) (bring-up) + [config/edge-cluster-ntnx1.json](config/edge-cluster-ntnx1.json) (Day 2, via [scripts/day2_ntnx1_networking.ps1](scripts/day2_ntnx1_networking.ps1)) |

### ⚠️ Read before starting

* **This is destructive.** It reinstalls ESX on the three SATADOMs and wipes the SSDs. On ntnx-1 that includes `NTNX1-Local` and `NTNX1-Local-Samsung` (≈6 GB used, so check what's on them first). It also ends Holodeck on NTNX1. The VIS depot and HoloRouter are now on esx-a, so they aren't touched.
* **The CPU is unsupported.** Broadcom discontinued Broadwell-EP in VCF 9.x, and Haswell-EP is older still. `allowLegacyCPU=true` turns the installer's hard stop into a warning; Haswell has the XSAVE instruction ESX requires. Expect future vLCM upgrades to need the same workaround, or to refuse.
* **The vSAN hardware is off the ESA HCL** (SATA SSDs on an LSI SAS3008). The `vsan.esa.sddc.managed.disk.claim` overrides bypass the HCL check, as upstream does for its consumer NVMe. ESA has run on these nodes before. The October 2026 partition was `VSAN.IgnoreClusterMemberListUpdates=1` on ntnx-2/3, and a fresh install resets that, but check it is `0` on every host after install (`esxcli system settings advanced list -o /VSAN/IgnoreClusterMemberListUpdates`).
* **ntnx-3's SAS3008 HBA can hang** (driver log: `lsi_msgpt3 ... Failed to init firmware`, no `vmhba2`, no SSDs). A warm reboot doesn't clear it; a full power-off does. This is what hid its third SSD (`naa.5002538c7000353b`) — the drive itself is healthy.
* **ntnx-3 has 2 SSDs, not 3, and bay 0 must stay empty.** Samsung `naa.5002538c70003543` went NOT READY and dropped off the HBA during an fio burn-in on 2026-10-21 and has been removed. Bay 0's link only negotiates SATA 3 Gb/s (half speed); the HPE `naa.5002538c404454b8` runs at full speed once moved to bay 1, so the fault is bay 0's backplane path, not the drive. A second 805 GB write+verify burn-in with the HPE in bay 1 passed, so bay 1 is fine and the removed Samsung was the bad part. Layout: HPE `…54b8` in bay 1, Samsung `…353b` in bay 2. ESA raw capacity is 3+3+2 = 8 × 960 GB ≈ 7.7 TB (about 5 TB usable with RAID-5 2+1 on 3 hosts).
* The VIS depot returned a `404` for `VCF_SALT_RAAS` 9.1.1.0100 during the Holodeck run. Watch for it at the binary-download step.

### Prerequisites

1. **Remove the three hosts from `uk-bhr-p-vc-1`.** They're in maintenance mode and not responding, so use *Remove from Inventory*.
2. **Create a VLAN 100 port group on DSwitch** for the installer VM on esx-a. Upstream calls it `DSwitch-VCF-Mgmt`: VLAN 100, default security. esx-a's switch ports already carry VLAN 100 (the `hosts` group on mikrotik-sw-1).
3. **Create the DNS records** in AD (`jameskilby.cloud`, forward **and** reverse). Create the reverse zone `100.168.192.in-addr.arpa` if it's missing. The ntnx A/PTR records currently point at 192.168.38.24–26 and must be **replaced**. Check that none of the new names already exist. [scripts/create_dns_records.ps1](scripts/create_dns_records.ps1) does all of this on the Windows DNS server: run it with `-WhatIf` first. It stops without changing anything if a name or IP is already in use by something else.

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
| uk-bhr-p-edge-1a / -1b | 192.168.100.50 / .51 | NSX Edge nodes (Day 2) |
| uk-bhr-p-vcf-proxy-1 | 192.168.100.55 | Ops cloud proxy |
| uk-bhr-p-vcf-asr-1 | 192.168.100.56 | Automation Services Runtime |
| uk-bhr-p-vcfa-1 | 192.168.100.57 | VCF Automation |
| — | 192.168.100.65–70 | Automation node pool |

Other networks:

| VLAN | Use | Addresses |
|---|---|---|
| 101 | vMotion vmk | 192.168.101.11–20 |
| 102 | vSAN vmk | 192.168.102.11–20 |
| 103 | Host TEP (NSX IP pool) | 192.168.103.11–30 |
| 104 | Edge TEP | edge-1a .11/.12, edge-1b .13/.14 |
| 105 | VM-Network port group `ntnx1-vm-network` | DHCP from sw-1 (.100–.200) |
| 106 | Tier-0 uplink 1 | edge-1a .2, edge-1b .3 → peer sw-1 .1 |
| 107 | Tier-0 uplink 2 | edge-1a .2, edge-1b .3 → peer sw-1 .1 |

4. **Pre-flight from something on VLAN 100** (e.g. the installer VM once it's up):
   * DNS really reaches AD: `dig @1.2.3.4 uk-bhr-p-vc-2.jameskilby.cloud` must *fail*. If it answers, port 53 is being hijacked the same way it is on VLAN 4.
   * NTP: `ntpdate -q 192.168.100.1` (mikrotik-sw-1 is the lab NTP server).
   * Depot: `curl -sI http://uk-bhr-p-vis-1.jameskilby.cloud:8081/PROD/metadata/productVersionCatalog/v1/productVersionCatalog.json` returns 200.
5. Tools on the Mac: `brew install xorriso govc`, plus PowerCLI.

### Installation

1. Build the per-host ISOs (default input: `~/Github/VMware-VMvisor-Installer-9.1.1.0100.25782009.x86_64.iso`):
   ```bash
   ./scripts/build_ks_isos.sh            # -> ./iso/ESX-NTNX-0{1,2,3}.iso
   ```
2. Mount `ESX-NTNX-0N.iso` on node N through its IPMI virtual media and boot from the virtual CD. The install is unattended and reboots twice. The host should come up at `https://uk-bhr-p-ntnx-N.jameskilby.cloud`, with all local SSDs showing as eligible (`vdq -q`).
3. Deploy the VCF Installer onto esx-a. It prompts for the vCenter password:
   ```bash
   ./scripts/deploy_vcf_installer.sh
   ```
4. Configure the installer (depot, override properties, service restart):
   ```powershell
   $env:VCENTER_PASSWORD = '...'; ./scripts/setup_vcf_installer.ps1
   ```
5. Open `https://uk-bhr-p-vcfi-1.jameskilby.cloud/` → *Depot settings and binary management* → download every binary until each one shows Success.
6. *Deploy using JSON spec* → upload [config/three-node-vsan-esa-tep-ntnx1.json](config/three-node-vsan-esa-tep-ntnx1.json). All passwords are `VMware123!VMware123!` (ESX root `VMware123!`), so change them in the JSON, the kickstarts and the scripts before using this for anything that isn't a lab. Acknowledge the CPU/HCL warnings, then deploy. Expect it to take several hours on this hardware.
7. **Day 2: Edges + VM-Network.** First add sw-1's side of the BGP sessions. The [iac](https://github.com/jameskilbycloud/iac) repo's `ansible/mikrotik/provision-vcf.yml` manages them (tag `nsx_edge_bgp`, peers and networks in `host_vars/mikrotik-sw-1/vcf.yml`: `nsx_edge_bgp_peers`, `nsx_edge_accept_networks`, `bgp_advertise_blocks`):
   ```bash
   cd ~/Github/iac/ansible/mikrotik
   ansible-playbook -i inventory.yml provision-vcf.yml --limit mikrotik-sw-1 --tags bgp
   ```
   It creates four eBGP connections from sw-1 (AS 65000) to the edges (AS 65100), edge-1a/1b on VLAN 106 and VLAN 107, and sends them only a default route. It accepts only the VPC external block (192.168.110.0/24 here, so pick yours and use it as the VPC external IP block in vCenter) and passes that block, including anything more specific inside it, on to the UniFi over the existing iBGP session. The UniFi session uses `nexthop-choice=force-self`, because otherwise the UniFi gets routes whose next hop is an edge address it can't reach. For reference, the resulting RouterOS config is:
   ```
   /routing filter rule
   add chain=nsx-edge-in rule="if (dst in 192.168.110.0/24) { accept }"
   add chain=nsx-edge-in rule="reject"
   add chain=nsx-edge-out rule="if (dst == 0.0.0.0/0) { accept }"
   add chain=nsx-edge-out rule="reject"
   add chain=bgp-vcf-out rule="if (dst in 192.168.110.0/24) { accept }" place-before=[find chain=bgp-vcf-out rule="reject"]
   /routing bgp connection
   set [find name=unifi] nexthop-choice=force-self
   add name=ntnx1-edge-1a-106 local.address=192.168.106.1 local.role=ebgp remote.address=192.168.106.2 remote.as=65100 as=65000 input.filter=nsx-edge-in output.default-originate=always output.filter-chain=nsx-edge-out
   add name=ntnx1-edge-1b-106 local.address=192.168.106.1 local.role=ebgp remote.address=192.168.106.3 remote.as=65100 as=65000 input.filter=nsx-edge-in output.default-originate=always output.filter-chain=nsx-edge-out
   add name=ntnx1-edge-1a-107 local.address=192.168.107.1 local.role=ebgp remote.address=192.168.107.2 remote.as=65100 as=65000 input.filter=nsx-edge-in output.default-originate=always output.filter-chain=nsx-edge-out
   add name=ntnx1-edge-1b-107 local.address=192.168.107.1 local.role=ebgp remote.address=192.168.107.3 remote.as=65100 as=65000 input.filter=nsx-edge-in output.default-originate=always output.filter-chain=nsx-edge-out
   ```
   Do this **before** creating the edge cluster: SDDC Manager's *Verify NSX BGP Peering* step waits for all four sessions, and on 2026-11-25 it sat retrying until the sw-1 side was added. Then run:
   ```powershell
   ./scripts/day2_ntnx1_networking.ps1
   ```
   The script validates and creates the Edge cluster through the SDDC Manager API, filling in the cluster ID itself, and adds the VLAN 105 `ntnx1-vm-network` port group. Creating the edge cluster took just under an hour on 2026-11-25, including about 10 minutes waiting on BGP. The two edge VM deploys took about 9 minutes each. Afterwards, finish the Centralized Transit Gateway / VPC external connection in vCenter against Tier-0 `ntnx1-m01-t0`.
8. Afterwards, power off and delete `uk-bhr-p-vcfi-1` and its DNS record. Optionally, add `esx-iscsi01` as supplemental storage: put the new host IQNs into TrueNAS initiator group 4 and rebuild vmk3/vmk4 (60.x/61.x) on the new VDS.

### Current state (2026-11-25)

Bring-up and the Day 2 edge cluster are done. The VPC external connection isn't configured yet.

| Component | State |
|---|---|
| Management domain | `ntnx1-m01`, cluster `ntnx1-mgmt-cl01` (3 hosts, vSAN ESA, 8 disks), vCenter `uk-bhr-p-vc-2` |
| Edge cluster | `ntnx1-m01-ec01` **ACTIVE**: `uk-bhr-p-edge-1a` / `-1b`, Medium form factor |
| Tier-0 | `ntnx1-m01-t0`, active-active, eBGP AS 65100 to sw-1 AS 65000 on VLAN 106 and 107 (keepalive 4 s, hold 12 s, no BFD). It redistributes Tier-1 connected routes. |
| Tier-1 | `ntnx1-m01-t1`, active-standby, advertises connected segments |
| BGP | all four edge sessions established. The edges get a default route; sw-1 learns only prefixes inside 192.168.110.0/24 and passes them to the UniFi. sw-1 uses one best path at a time (no ECMP). |
| Test segment | `bgp-test`, 192.168.110.240/28 (gateway .241, DHCP .243–.254) on Tier-1 `ntnx1-m01-t1`, transport zone `vcf-overlay-TZ`. `bgptestvm` (.243) is reachable from the LAN: UniFi → sw-1 (192.168.15.1) → edge (192.168.106.x) → Tier-1 → VM. |
| VPCs | none yet. There's no 192.168.110.0/24 IP block in NSX, and the default VPC connectivity profile has no external blocks. |

Notes:
* Put overlay segments in **`vcf-overlay-TZ`**. The edges and hosts are members of that zone, not of `nsx-overlay-transportzone`.
* Segments that should be reachable from the LAN need a subnet inside 192.168.110.0/24, because sw-1's `nsx-edge-in` filter drops anything else. The `bgp-test` /28 sits inside that block, so keep it out of the VPC external IP block, or delete the segment first.
* SDDC Manager's *Downloading Esx metadata, vibs and vendor add-ons* task has failed on every run since October 2026, most recently 2026-11-25. It's the online depot download and doesn't affect running workloads.

### Shutting down and starting up NTNX1

[scripts/shutdown_ntnx1_vcf.sh](scripts/shutdown_ntnx1_vcf.sh) guest-shuts-down the VCF VMs through `uk-bhr-p-vc-2`, one layer at a time and top-down. The order is VCF Automation → cloud proxy → VCF Operations → management services runtime → License Server → NSX Edges → NSX Manager → SDDC Manager, and it waits for each layer to power off before starting the next. Before starting, it checks that every host is connected and that vSAN isn't resyncing. Run it with `--dry-run` first. It stops at vCenter: finish with **vSAN → Shutdown Cluster** on `ntnx1-mgmt-cl01`, which shuts down vCenter last and powers off the hosts.

To start up again:
1. Power on the hosts.
2. Wait for vCenter, then run **vSAN → Restart Cluster**.
3. Run [scripts/startup_ntnx1_vcf.sh](scripts/startup_ntnx1_vcf.sh) (`--dry-run` first). It checks that every host is connected and out of maintenance mode, that all 8 vSAN disks are present and that no vSAN objects are inaccessible. Then it powers the appliances on bottom-up: SDDC Manager → NSX → Edges → License Server → management services runtime → VCF Operations → cloud proxy → VCF Automation. It waits for each one to answer: the SDDC Manager API token, NSX cluster `STABLE`, or the service's HTTPS endpoint answering with a status below 500.

#### Automating the vSAN steps (`--vsan`)

Add `--vsan` to either script to have it do the vSAN step too, through the vSAN management API ([scripts/vsan_cluster_power.py](scripts/vsan_cluster_power.py), Python standard library only):
* `shutdown_ntnx1_vcf.sh --yes --vsan` runs **Shutdown Cluster** once the VMs are off, then waits until vCenter and all three hosts have powered off.
* `startup_ntnx1_vcf.sh --yes --vsan` can be run as soon as the hosts are powered on. It waits up to an hour for vCenter and every host to connect, runs **Restart Cluster** if the cluster isn't fully powered on, and then carries on with the pre-checks and the appliances. With `--dry-run --vsan` it reports whether a restart is needed and stops there, since the other pre-checks only pass after it.

`vsan_cluster_power.py status <cluster-moref>` prints the cluster's vSAN power state (`clusterPoweredOn` when fully up).

**Timings.** The first full `startup_ntnx1_vcf.sh --yes --vsan` run, on 2026-11-25 with the hosts already powered on, took 32 minutes:

| Step | Time |
|---|---|
| vSAN Restart Cluster | 75 s |
| SDDC Manager | 2 min |
| NSX Manager | 6 min |
| License Server | 3 min |
| Management services runtime | 80 s |
| VCF Operations | 20 s |
| Cloud proxy | 40 s |
| VCF Automation | 100 s |

Each layer then waits a further 2 minutes for services to settle. The `http:` readiness check passes as soon as a front end answers below 500, so VCF Operations, the cloud proxy and the management services runtime can count as ready before their services are fully up. VCF Automation can take another 15–30 minutes before it accepts logins.

**Home Assistant** runs both scripts, with `--vsan`, from the *VCF 9.1 Lab (NTNX1)* section of its Homelab dashboard. It has dry-run buttons, an arm switch for real runs and a live log. A real startup powers the nodes on through their BMCs first if any is off, and shows a countdown of about 35 minutes. HA keeps copies of the scripts under `vcf/` in its config repo, so update those when the scripts here change.

ntnx-3's power-on is a cold boot, so its SAS3008 comes back normally; still check that all 8 SSDs are present.

## Post Installation

![](screenshots/screenshot-15.png)

There are a number of [post-VCF deployment optimizations](https://williamlam.com/2026/04/automating-lab-optimizations-for-post-deployment-of-vmware-cloud-foundation-vcf.html) that should be run for lab environments. You can refer to the linked blog post and run the PowerShell script `vcf-post-deploy-lab-tweaks.ps1`.

For NTNX1, use [scripts/post_deploy_lab_tweaks_ntnx1.ps1](scripts/post_deploy_lab_tweaks_ntnx1.ps1), an adapted copy with NTNX1's endpoints. It targets `ntnx1-mgmt-cl01` by name and leaves CEIP accepted, as upstream does. Run it only after the cluster is healthy: it silences every vSAN health check that's yellow at the time, so it skips that step unless all 8 vSAN disks are present. The other changes are disabling HA admission control, clearing triggered vSAN alarms, hiding the NSX telemetry prompt and VCF Operations banner, disabling the NSX `logging.remote_logging_not_configured` and `capacity.minimum_capacity_threshold` alarms, and setting NSX backups to every 12 hours. The script header says how to undo each one.

![](screenshots/screenshot-16.png)

## Additional Blog Resources

* [VMware Cloud Foundation (VCF) on Minisforum MS-A2](https://williamlam.com/2025/06/vmware-cloud-foundation-vcf-on-minisforum-ms-a2.html)
   * [VCF 9.x Hardware BOM for Silicon Valley VMUG](https://williamlam.com/2025/07/vcf-9-0-hardware-bom-for-silicon-valley-vmug.html)
   * [My VCF 9 Lab Mini-Rack](https://williamlam.com/2025/10/my-vcf-9-lab-mini-rack.html)
* [VCF 9.1 Resources](https://williamlam.com/vmware-cloud-foundation-9)
---
title: 'Optimizing a NixOS-based NAS'
description: 'From Legacy IDE to questionable (but stable?) performance optimizations'
pubDate: 2025-09-25
---

Project repo: [https://github.com/b4lisong/nix-config](https://github.com/b4lisong/nix-config)

In this post, I'll walk through the optimization of a NixOS-based NAS running on HP MicroServer Gen8 hardware,
covering topics from ZFS memory management to storage performance tuning. Apparently, I find this more fun
than just installing TrueNAS and calling it a day. I might wish I just did that by the end, though.

## Hardware Foundation: HP MicroServer Gen8

The HP MicroServer Gen8 was (is? Are y'all still buying this thing? Anyone want to buy mine?) 
a popular choice for home NAS builds, but it comes with some unique ~pains-in-the-ass~ challenges:

- **CPU**: Intel Xeon E3-1220L v2 (4 cores, 16GB RAM)
- **Storage**: 4x4TB drives in internal bays + 500GB SSD in ODD port
- **Network**: Gigabit Ethernet
- **Quirk**: ODD port cannot boot in AHCI mode (requires workaround)

### ~The Stupid No UEFI Boot Problem~
### The AHCI Boot Problem

One of the first challenges was getting optimal SATA performance. Actually, the first challenge
was trying to get Proxmox installed, and that was so frustrating due to the finnicky image and no UEFI that I 
gave up, and said "fuck it, we're going Nix." (Yes, I tried just installing Proxmox over Debian and ran into more
annoying issues).


ANYWAY


The HP MicroServer Gen8's Optical Disk Drive (ODD) port - where the system SSD lives - cannot 
boot directly in AHCI mode. Go figure. First, I tried a popular suggestion from Google and the SpiceWorks
forums that involved setting the BIOS to Legacy IDE SATA instead of AHCI and switching the controller order.
This "worked." It could boot, but with garbage performance.

The *actual* solution required a (thankfully well-documented) ~stupid~ creative workaround:

1. **Boot device**: Internal SD card with GRUB bootloader
2. **System storage**: 500GB SSD in ODD port with ZFS root filesystem
3. **Boot sequence**: SD card → GRUB → ZFS root on SSD

This configuration allows AHCI mode for all drives while maintaining reliable booting.
The NixOS configuration reflects this setup:

```nix
# Internal SD card for bootloader (HP MicroServer Gen8 workaround)
boot.loader.grub.device = "/dev/disk/by-id/usb-HP_iLO_Internal_SD-CARD_000002660A01-0:0";

# AHCI kernel module support
boot.initrd.availableKernelModules = [ "ehci_pci" "ahci" "ata_piix" "..." ];
```

### The IDE vs AHCI Performance Disaster

But first, let me tell you *why* this workaround was absolutely critical. 
Initially, I had the system running in legacy IDE mode because it was the path of least resistance - 
everything just worked. The SSD could boot, ZFS was happy(?), life was good.

**Life was not good.**

When I finally got around to running performance tests, the results were... let's call them "character building":

12 MB/s sequential write performance. My storage pool was getting diffed by USB2.

**IDE Mode Performance (Legacy/Compatibility):**
- **Queue Depth**: All drives locked to 1 or 2 (no NCQ support)
- **I/O Schedulers**: Limited options, poor ZFS integration
- **Drive Recognition**: Some drives mis-identified as spinning when they were SSDs
- **Overall Performance**: Absolutely abysmal across the board

The specific smoking gun was seeing drives that I *knew* were capable of 32-deep command queues and 100+ MB/s 
throughput performing like they were from 2005. Write caching was inconsistent, 
NCQ (Native Command Queueing) was completely disabled, and the entire storage subsystem 
felt like it was running through molasses.

This is what finally motivated the SD card + AHCI workaround. The performance difference was night and day:

**IDE Mode → AHCI Mode Improvements:**
- **Queue Depth**: 1-2 → 32 (proper NCQ support)
- **Write Caching**: Inconsistent → Properly enabled across all drives
- **Drive Detection**: Fixed SSD/HDD classification
- **I/O Scheduler Options**: Limited → Full range of modern schedulers

The transition from IDE to AHCI mode was the single biggest performance improvement 
in this entire project - easily 2-3x better performance before any other optimizations,
and almost an order of magnitude better in some metrics (sequential).

**Lesson learned**: Sometimes "it just works" is the enemy of "it works well." 
The HP MicroServer Gen8's IDE mode for ODD boot is functional, 
but leaves massive performance on the table.

## Storage Architecture: ZFS RAIDZ1 Configuration

The storage setup uses ZFS in a RAIDZ10-like configuration:

- **Root pool (`rpool`)**: Single SSD with datasets for `/`, `/nix`, `/var`, `/home`, `/incus`
- **Storage pool (`storage`)**: 4x4TB drives in RAIDZ1 mirror configuration with datasets for `/mnt/app_config`, `/mnt/media`, `/mnt/backup`

This provides redundancy while maximizing usable space - decent 
for a home NAS handling media files and application data.

## Memory Management: The ZFS ARC Challenge

### The Problem

With only 16GB of RAM serving as both a NAS and KVM hypervisor, memory management becomes critical. 
ZFS's Adaptive Replacement Cache (ARC) can consume most available memory, starving virtual machines and system processes.
Many of you may believe that this hardware would be better off ~in the garbage~ being dedicated to a storage workload
or a light VM workload, and I'd be inclined to agree. But it's what I have for now so we're going with it.

Initial symptoms:
- VMs experiencing memory pressure
- System responsiveness issues under load
- Unpredictable memory allocation

### The Solution

Setting explicit ZFS ARC limits through kernel module parameters:

```nix
boot.extraModprobeConfig = ''
  # ZFS ARC memory limits for KVM hypervisor with 16GB RAM
  options zfs zfs_arc_max=4294967296  # 4GB maximum
  options zfs zfs_arc_min=1073741824  # 1GB minimum
'';
```

**Memory allocation result:**
- ZFS ARC: 4GB maximum (25% of total RAM)
- zram swap: 4GB (existing configuration)
- Available for KVM/system: ~8GB

This 25% allocation strikes a balance between ZFS caching performance and system memory availability.

## Storage Performance Analysis

### Baseline Testing

Before optimization, comprehensive performance testing revealed several bottlenecks using `fio` benchmarks:

**ZFS Storage Pool Performance Issues:**
- **Random 4K I/O**: 190 read IOPS / 48 write IOPS
- **Sequential large files**: 13.2 MB/s read / 32.1 MB/s write
- **Multi-user (4 clients)**: 366 read IOPS / 125 write IOPS

**Individual Drive Performance (baseline):**
- **Raw HDD performance**: 975 read IOPS / 416 write IOPS
- **Sequential**: 107 MB/s read/write

The data showed an 80% performance drop from raw drives to ZFS - clearly indicating optimization opportunities.

### Root Cause Analysis

Investigation revealed several performance bottlenecks:

1. **I/O Scheduler conflicts**: Mixed schedulers (`none`, `mq-deadline`) fighting with ZFS's internal scheduling
2. **ZFS parameter defaults**: Conservative settings optimized for safety over performance
3. **Write performance**: 4:1 read/write IOPS ratio suggested transaction group bottlenecks

## Performance Optimization Strategy

### Test-Driven Approach

Rather than applying generic optimizations, each change targeted specific bottlenecks identified in the performance data:

**1. I/O Scheduler Optimization**
```nix
services.udev.extraRules = ''
  # Set 'none' scheduler for ZFS drives using stable identifiers
  ACTION=="add|change", ENV{ID_SERIAL}=="WDC_WDS500G1R0A-68A4W0_2041DA803271", ATTR{queue/scheduler}="none"
  ACTION=="add|change", ENV{ID_SERIAL}=="ST4000VN006-3CW104_ZW6034KJ", ATTR{queue/scheduler}="none"
  # ... additional drives

  # Keep mq-deadline for SD cards (optimal for flash storage)
  ACTION=="add|change", ENV{ID_SERIAL}=="HP_iLO_Internal_SD-CARD_000002660A01", ATTR{queue/scheduler}="mq-deadline"
'';
```

**2. ZFS Kernel Module Tuning** - Addresses multi-user bottleneck
```nix
boot.extraModprobeConfig = ''
  # ZFS performance optimization based on test results
  options zfs zfs_vdev_max_active=3000        # 3x concurrent operations
  options zfs zfs_top_maxinflight=320         # Better queue depth utilization
  options zfs zfs_prefetch_disable=0          # Ensure prefetch enabled
  options zfs zfs_txg_timeout=5               # Faster transaction commits
  options zfs zfs_dirty_data_max_percent=25   # More dirty data buffer
'';
```

**3. Network Buffer Optimization** - Maintains streaming performance
```nix
boot.kernel.sysctl = {
  # Network buffer optimization for high-bandwidth NAS workloads
  "net.core.rmem_max" = 16777216;
  "net.core.wmem_max" = 16777216;
  "net.ipv4.tcp_rmem" = "4096 65536 16777216";
  "net.ipv4.tcp_wmem" = "4096 65536 16777216";
  # ... additional network tuning
};
```

### Results: Measured Improvements

Post-optimization testing showed consistent 6-7% improvements across all workloads:

- **ZFS Random I/O**: 190 → 202 read IOPS (+6%), 48 → 51 write IOPS (+6%)
- **ZFS Large Files**: 13.2 → 13.9 MB/s read (+5%), 32.1 → 34.3 MB/s write (+7%)
- **Multi-user**: 366 → 389 read IOPS (+6%), 125 → 134 write IOPS (+7%)
- **Media Streaming**: Maintained excellent 7.7 GB/s performance

While these improvements might be marginal, they represent meaningful gains without 
introducing system instability. The real gains are probably from better hardware. 

## Network File Sharing: Samba Configuration

### Secure Multi-User Setup

The NAS provides network file sharing through Samba with a security-focused approach:

```nix
services.samba = {
  enable = true;
  settings = {
    global = {
      "workgroup" = "WORKGROUP";
      "netbios name" = "nas";
      "security" = "user";
      # Network access limited to private ranges
      "hosts allow" = "192.168. 10. 127.";
      "hosts deny" = "0.0.0.0/0";
      # Performance settings
      "server min protocol" = "SMB2";
      "use sendfile" = "yes";
    };
  };
};
```

### User Management Strategy

Rather than exposing individual user accounts, the configuration uses a dedicated group approach:

```nix
# Custom group for NAS dataset access
users.groups.nas-users = {
  gid = 1000; # Fixed GID for consistent SMB/NFS sharing
};

# Service user for Samba access
users.users.nas-user = {
  isSystemUser = true;
  description = "NAS Samba service user";
  group = "nas-users";
  createHome = false;
};
```

This approach provides clean separation between system administration and file sharing access.

### Dataset Permissions and Automation

ZFS datasets are automatically configured with appropriate permissions via systemd services:

```nix
systemd.services.nas-storage-permissions = {
  description = "Set permissions on NAS storage datasets";
  after = [ "zfs-mount.service" ];
  wantedBy = [ "multi-user.target" ];
  script = ''
    # Set ownership and permissions for storage datasets
    chown root:nas-users /mnt/app_config /mnt/media /mnt/backup
    chmod 2775 /mnt/app_config /mnt/media /mnt/backup
  '';
};
```

The `2775` permissions with sticky group bit ensure all files created maintain group ownership, 
critical for multi-user NAS environments.

## Performance Testing Infrastructure

### Comprehensive Benchmarking

The optimization process relied heavily on systematic performance testing. Custom scripts provided repeatable benchmarks:

**Queue Depth Analysis:**
```bash
#!/usr/bin/env bash
# Check current queue depth for all drives
for drive in /dev/sd?; do
  echo "=== $drive ==="
  echo "Queue depth: $(cat /sys/block/$(basename $drive)/queue/nr_requests)"
  echo "Scheduler: $(cat /sys/block/$(basename $drive)/queue/scheduler)"
done
```

**Storage Performance Testing:**
- SSD random 4K I/O (database-like workload)
- HDD sequential throughput (streaming media)
- ZFS dataset performance (real-world NAS usage)
- Multi-client concurrent access (Plex/media server simulation)

### Validation and Monitoring

Performance improvements were validated through before/after comparisons with identical test parameters. 
This data-driven approach ensured optimizations provided real benefits rather than synthetic benchmark improvements.

## Lessons Learned

### 1. Hardware Constraints Drive Architecture

The HP MicroServer Gen8's ODD port boot limitation forced a solution using the internal SD card. 
This might even reliability by separating boot and storage concerns, if my SD card doesn't crap out.

### 2. Memory Management is Critical

In constrained memory environments, explicit ZFS ARC limits prevent resource conflicts. 
The 25% allocation rule might be optimal for mixed workloads, with respect to my hardware limits.

### 3. Test-Driven Optimization Works, Probably

Rather than applying random "performance tips" from Reddit,
measuring actual bottlenecks and targeting specific issues yielded 
some(?) improvements without instability. Probably?

### 4. NixOS Configuration Management Shines

Declarative configuration made it easy to:
- Version control all system changes
- Apply consistent settings across rebuilds
- Document optimization rationale alongside implementation

## The NixOS Advantage

This project highlights several NixOS strengths for infrastructure projects:

**Declarative Configuration:** All settings, from kernel parameters to service configuration, live in version-controlled `.nix` files.

**Reproducible Builds:** The entire system can be rebuilt identically from configuration files.

**Rollback Safety:** Bad configurations can be easily reverted through NixOS generations.

**Integration:** Complex multi-service setups (ZFS + Samba + systemd + udev rules) integrate cleanly through the module system.

## Future Improvements

While the current setup performs well, several optimization opportunities remain:

1. **ZFS SLOG device**: Adding a small SSD as a dedicated intent log could significantly improve sync write performance
2. **L2ARC expansion**: Additional SSD cache could extend the effective ARC size
3. **Samba optimization**: Protocol-level tuning for specific client workloads
4. **Currency-unconstrained hardware refactoring**: Just get rid of this damn thing and buy better hardware.

## Conclusion

Building a NAS involves balancing multiple competing concerns: storage performance, memory management, network optimization, and service reliability. 
This HP MicroServer Gen8 build demonstrates how to over-engineer turd-polishing for acceptable performance. 

The combination of ZFS's advanced features, NixOS's configuration management, 
and some tuning resulted in a stable storage system suitable for both home media serving 
and development workloads.

Most importantly, the entire configuration is documented, version-controlled, and reproducible 
- ensuring this investment in optimization pays dividends until I decide to give up on Nix.

---
Project repo: [https://github.com/b4lisong/nix-config](https://github.com/b4lisong/nix-config)

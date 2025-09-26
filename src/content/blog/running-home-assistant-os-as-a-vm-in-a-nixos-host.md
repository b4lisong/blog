---
title: 'Running Home Assistant OS as a VM in a NixOS Host'
description: ''
pubDate: 2025-09-26
---

## Introduction

I have a "smart" home. I like NixOS. Configuring things is fun. 
Also, my previous Proxmox host, which used to house my Home Assistant VM, is being repurposed
for Windows Server, and I don't feel like putting Home Assistant on one of my Raspberry Pis because
that would just make too much sense (I might end up doing this later anyway).

Now that I've moved my NAS to NixOS, I want to fully utilize the remaining available resources,
so a Home Assistant migration was in order. I chose Incus as my ~"we have Proxmox at home"~ "Proxmox-lite"
solution as it seems to be decently supported and has a graphical web front-end to make management easier.
Trouble is, I've never used Incus before, and getting Home Assistant OS in a Proxmox VM to work was as easy
as running a helpful [pre-made script](https://community-scripts.github.io/ProxmoxVE/scripts?id=haos-vm).

There's tutorials for Incus on NixOS. There's tutorials for Home Assistant on Incus. This one is for both.
I'm assuming you're already familiar with NixOS and flakes.

Heavily leveraging the work done by Scotti-Byte in the following tutorials:
- [Incus Containers Step by Step](https://discussion.scottibyte.com/t/incus-containers-step-by-step/349)
- [Home Assistant OS in Incus 101](https://discussion.scottibyte.com/t/home-assistant-os-in-incus-101/648)

The final setup provides:
- HomeAssistant OS running in an Incus VM
- VM gets its own IP from your router's DHCP
- Optimal device discovery for IoT integration
- Clean, declarative NixOS configuration
- ZFS storage integration

## System Overview
- [Project repo](https://github.com/b4lisong/nix-config)
- [Hardware & Storage Setup](https://balisong.dev/blog/optimizing-a-nixos-based-nas/)

### Hardware Setup
- **Host**: HP MicroServer Gen8 (16GB RAM, x86_64)
- **Storage**: ZFS root pool on 500GB SSD + ZFS data pool on 4x4TB drives
- **Network**: Single ethernet interface with bridge networking
- **OS**: NixOS with Incus virtualization

### Architecture
```
[Router DHCP] ←→ [Physical Network] ←→ [eno1] ←→ [br0 Bridge] ←→ [VM]
                                              ↑
                                        [Host also gets IP]
```

Both the NixOS host and HomeAssistant VM get separate IP addresses from the same router, appearing as independent devices on the network.

## NixOS Configuration

### Step 1: Enable Incus with ZFS Storage
Skip the ZFS part if you aren't using ZFS, but define a storage pool somewhere.

```nix
# In hosts/linux-nas/default.nix
virtualisation = {
  # Incus virtualization
  incus = {
    enable = true;
    ui.enable = true;  # Enable web UI
    preseed = {
      networks = [
        {
          name = "incusbr0";
          type = "bridge";
          config = {
            "ipv4.address" = "10.0.100.1/24";
            "ipv4.nat" = "true";
          };
        }
      ];
      storage_pools = [
        {
          name = "zfs-incus";
          driver = "zfs";
          config = {
            source = "rpool/incus";  # Use existing ZFS dataset
          };
        }
      ];
      profiles = [
        {
          name = "default";
          devices = {
            eth0 = {
              name = "eth0";
              network = "incusbr0";
              type = "nic";
            };
            root = {
              path = "/";
              pool = "zfs-incus";
              type = "disk";
            };
          };
        }
      ];
    };
  };

  # Also enable libvirtd for virt-manager
  libvirtd = {
    enable = true;
    qemu = {
      package = pkgs.qemu_kvm;
      ovmf.enable = true;
      ovmf.packages = [ pkgs.OVMF ];
    };
  };
};
```

### Step 2: Configure Bridge Networking

Using NixOS's native bridge support instead of fighting with NetworkManager:

```nix
networking = {
  # Disable NetworkManager in favor of simple bridge configuration
  networkmanager.enable = false;
  # Use systemd-networkd for bridge management
  useNetworkd = true;
  # Required for Incus networking
  nftables.enable = true;
  # Disable firewall for simplified setup (local network only)
  firewall.enable = false;

  # Create bridge interface with NixOS
  bridges.br0 = {
    interfaces = [ "eno1" ];  # Your ethernet interface
  };

  # Configure bridge with DHCP
  interfaces.br0 = {
    useDHCP = true;
  };
};
```

This configuration:
- Creates a `br0` bridge that includes your physical ethernet interface
- Gets an IP address via DHCP from your router
- Provides a stable bridge that Incus can reference
- Eliminates NetworkManager conflicts

I prefer setting DHCP and having my router statically assign an IP on its end. Your choice.

### Step 3: User Permissions

```nix
users.users.${myvars.user.username} = {
  extraGroups = [
    # ... existing groups ...
    "incus-admin"  # Access to Incus management
    "libvirtd"     # Access to libvirt
  ];
};
```

### Step 4: Install Virtualization Packages

```nix
environment.systemPackages = with pkgs; [
  # Virtualization packages
  qemu_kvm         # QEMU with KVM support
  virt-manager     # GUI for VM management
  libvirt          # libvirt client tools
  bridge-utils     # Network bridge utilities
];
```

You can choose to load these tools into an ephemeral shell with `nix-shell -p` if you want.
They are for converting the HA OS image in this tutorial. I wanted to keep them for the future
so I made them part of my system configuration.

## Deployment and VM Creation

### Deploy the Configuration

```bash
# Test the configuration
nix flake check

# Deploy to your NixOS host
nixos-rebuild switch --flake .#linux-nas 
```

### Create Bridged Profile

After deployment, create an Incus profile that uses the host bridge:

```bash
# On your NixOS host

# Create bridged profile that uses host br0 bridge directly
incus profile create bridgeprofile

# Add network device connected directly to host bridge
incus profile device add bridgeprofile eth0 nic \
  nictype=bridged \
  parent=br0 \
  name=eth0

```
### Download and Import HomeAssistant OS

```bash
# Download "QEMU-friendly" HomeAssistant OS VM image
wget https://github.com/home-assistant/operating-system/releases/download/15.2/haos_ova-15.2.qcow2.xz

# Extract the image
xz -d "haos_ova-15.2.qcow2.xz"

# Get incus-migrate
wget https://github.com/lxc/incus/releases/latest/download/bin.linux.incus-migrate.x86_64
mv bin.linux.incus-migrate.x86_64 incus-migrate && chmod +x incus-migrate
./incus-migrate
```

Follow the prompts (reference [Home Assistant OS in Incus 101](https://discussion.scottibyte.com/t/home-assistant-os-in-incus-101/648)):
1. `Yes` (local Incus server target)
2. `2` (Virtual Machine)
3. `HA-OS` (name of the new instance, name it whatever you like)
4. `haos_ova-15.2.qcow2` (path to image file)
5. `Yes` (UEFI booting)
6. `No` (Secure booting)
7. `2` (additional override profile list)
8. `default bridgeprofile` (to have an address on the main LAN)
9. `1` (perform the migration)

Here, I decided on setting the disk size and memory allocation:
```bash
incus config device override HA-OS root size=50GiB   
incus config set HA-OS limits.memory 4GiB
```

### Launch HomeAssistant VM

```bash
incus start HA-OS
# Check VM status
incus list
```

## Verification and Access

### Check Network Configuration

```bash
# Verify host bridge has IP
ip addr show br0

# Verify VM has different IP from same network
incus list
```

Example output:
```
# Host bridge
br0: inet 192.168.1.100/24

# VM
homeassistant    192.168.1.150    RUNNING
```

### Access HomeAssistant

1. **Wait for boot**: HomeAssistant OS takes 5-10 minutes to initialize
2. **Access web interface**: `http://your-host-ip:8123`
3. **Complete setup wizard**: Create admin user and configure

### Verify Device Discovery

The VM should now be able to:
- Discover IoT devices on your local network
- Be accessible from other devices on your network
- Function as if it were a physical HomeAssistant device

## Key Benefits

### Network Integration
- **Separate IP address**: VM appears as independent device
- **Device discovery**: HomeAssistant can find IoT devices
- **Direct access**: Other devices can reach HomeAssistant directly
- **Router DHCP**: Uses existing network infrastructure

### Management
- **Incus web UI**: Manage VMs through browser interface
- **NixOS integration**: Declarative configuration
- **Clean networking**: No complex NetworkManager conflicts
- **Simple maintenance**: Standard Incus and NixOS tools

## Troubleshooting

### VM Network Issues
```bash
# Check bridge status
brctl show br0

# Verify Incus profile
incus profile show bridgeprofile

# Check VM network interface
incus exec homeassistant -- ip addr show
```

### Access Incus Web UI
Access the management interface at `https://your-host-ip:8443`

### Performance Tuning
- **CPU**: Start with 2 vCPUs, increase if needed
- **Memory**: 4GB is sufficient for most setups; Scotty went with 6.
- **Disk**: 32GB handles HomeAssistant + add-ons; I went with 50 GB just in case.

## Conclusion

This setup provides a production-ready HomeAssistant environment that:
- Leverages NixOS's declarative configuration
- Uses reliable ZFS storage
- Provides optimal network integration
- Supports the full HomeAssistant ecosystem

The result is a HomeAssistant VM that behaves exactly like a dedicated hardware device, 
on Incus and NixOS.

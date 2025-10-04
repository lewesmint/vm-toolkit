# VM Hostname Resolution Workflow

## Overview
Understanding how a VM goes from boot to having working hostname resolution (`ping fargo` works).

## The Complete Workflow

### 1. VM Creation & Boot
```
vm start fargo
├── QEMU starts with MAC: 52:54:00:15:7a:e3
├── VM boots Ubuntu 24.04
├── Network interface ens3 comes up
└── Cloud-init starts network configuration
```

### 2. Network Interface Initialization
```
ens3 interface initialization:
├── Gets MAC address: 52:54:00:15:7a:e3
├── Sends DHCP request to router (192.168.1.254)
├── Router assigns IPv4: 192.168.1.xxx
└── Interface configured with both IPv4 and IPv6
```

### 3. Cloud-init Logging (The Issue)
```
Cloud-init network logging:
├── First boot: Only logs IPv6 address to console.log
├── Later boots: Logs both IPv4 and IPv6 to console.log
└── Timing issue: IPv4 might be assigned after logging phase
```

### 4. DNS Registration
```
VM registers with local DNS:
├── VM sends hostname "fargo" to DHCP server
├── Router/DNS server (192.168.1.254) registers:
│   ├── Hostname: fargo
│   ├── IPv4: 192.168.1.xxx
│   └── MAC: 52:54:00:15:7a:e3
└── DNS entry becomes available network-wide
```

### 5. ARP Table Population
```
Host ARP table gets populated:
├── When VM responds to network traffic
├── Entry format: ? (192.168.1.xxx) at 52:54:0:15:7a:e3 on en0
└── Note: macOS strips leading zeros in MAC
```

### 6. Final State - Everything Works
```
ping fargo works because:
├── DNS resolves "fargo" → 192.168.1.xxx
├── Ping sends packets to 192.168.1.xxx
├── VM responds from 192.168.1.xxx
└── ARP table maps IP ↔ MAC
```

## The Detection Problem

### What We're Trying to Detect
- **Goal**: Find VM's IPv4 address for status display
- **Challenge**: Multiple detection methods with different reliability

### Detection Methods (In Order of Preference)

#### Method 1: Console Log Parsing ⭐ (Most Reliable)
```bash
# Look for cloud-init network table
grep -E '([0-9]{1,3}\.){3}[0-9]{1,3}.*([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}' console.log
```
**Pros**: Fast, reliable when it works
**Cons**: Sometimes IPv4 not logged on first boot

#### Method 2: Registry Cache (Fast Fallback)
```bash
# Check cached IP from previous detection
jq -r ".vms[\"$vm_name\"].ip_address" registry.json
```
**Pros**: Very fast
**Cons**: May be stale, needs validation

#### Method 3: ARP Table Lookup (Slow Fallback)
```bash
# Find IP by MAC address
timeout 2 arp -a | grep "52:54:00:15:7a:e3"
```
**Pros**: Works when VM has IP
**Cons**: Slow, MAC format issues (leading zeros)

#### Method 4: Hostname Resolution (Alternative)
```bash
# Resolve hostname to IP
nslookup fargo | grep "Address:" | grep -v ":"
```
**Pros**: Works when DNS is registered
**Cons**: Requires hostname resolution to be working

## The Status State Machine

### Desired Status States
```
VM Status Flow:
├── missing     → VM directory doesn't exist
├── stopped     → Process not running
├── initializing → Process running, no IPv4 detected
├── booting     → Has IPv4, SSH not ready (port 22 closed)
└── running     → Has IPv4, SSH ready (port 22 open)
```

### Current Problem
- Status shows "running" even when no IP detected
- Should show "initializing" until IP is confirmed

## Timeline Example: Fargo VM

```
T+0s:   vm start fargo
T+5s:   QEMU process starts (PID: xxxxx)
T+10s:  Ubuntu kernel boots
T+15s:  Network interface ens3 up
T+20s:  DHCP request sent
T+25s:  IPv6 address assigned (logged to console)
T+30s:  IPv4 address assigned (NOT logged to console on first boot)
T+35s:  DNS registration with router
T+40s:  SSH daemon starts
T+45s:  ping fargo works (DNS + IPv4 working)
T+50s:  ssh fargo works (SSH ready)
```

## Solutions to Explore

### 1. Improve Console Log Detection
- Handle both IPv4 and IPv6 logging patterns
- Extract MAC from IPv6 line, use for ARP lookup

### 2. Optimize ARP Detection
- Use timeout to prevent hanging
- Handle macOS MAC format (leading zero stripping)
- Limit search scope to local subnet

### 3. Add Hostname Resolution Fallback
- Use `nslookup` when other methods fail
- Fast and reliable when DNS is working

### 4. Fix Status State Logic
- Don't show "running" until IP is confirmed
- Implement proper state transitions

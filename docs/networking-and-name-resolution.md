# Networking & Name Resolution

This guide explains VM networking modes, how the toolkit finds the “best IP” for your VMs on macOS, and how to keep local name resolution accurate.

---

## Network Modes

The toolkit supports two networking modes via Apple's vmnet framework. Both require sudo for vmnet access.

### Bridged Mode (Default) — `--net bridged`

VMs join your local network directly via a bridge interface (typically `en0` for WiFi or Ethernet).

| Property | Value |
|----------|-------|
| **IP Range** | Your LAN subnet (e.g., `192.168.1.x`) |
| **DHCP Server** | Your router |
| **Visibility** | VMs are full LAN citizens, visible to other devices |
| **Use Case** | Production-like networking, multi-VM clusters, accessing VMs from other machines |

```bash
# Start with bridged networking (default)
vm start myvm

# Explicitly specify bridged mode
vm start myvm --net bridged

# Use a specific interface (e.g., Ethernet instead of WiFi)
vm start myvm --net bridged --bridge en1
```

### Shared Mode — `--net shared`

Apple's built-in NAT. VMs get IPs from a private subnet managed by vmnet.

| Property | Value |
|----------|-------|
| **IP Range** | `192.168.105.x` (Apple's vmnet-shared subnet) |
| **DHCP Server** | macOS vmnet |
| **Visibility** | VMs can reach the internet but are not directly accessible from other LAN devices |
| **Use Case** | Simple internet access, isolated VMs, avoiding router DHCP issues |

```bash
# Start with shared (NAT) networking
vm start myvm --net shared
```

### Choosing a Mode

| Need | Recommended Mode |
|------|------------------|
| SSH from Mac host only | Either works |
| VMs need to talk to each other | Bridged |
| VMs accessible from other LAN machines | Bridged |
| Simple isolated development | Shared |
| Router has DHCP issues over WiFi | Shared (or fix router) |

---

## ⚠️ Bridged Mode over WiFi: Known Limitations

**Bridged networking over WiFi on Apple Silicon Macs has inherent limitations** due to how WiFi works differently from Ethernet.

### The Problem

WiFi access points typically associate a single MAC address per client. When you use bridged mode:

1. Your Mac's WiFi adapter has MAC `AA:AA:AA:AA:AA:AA`
2. Your VM sends packets with its own MAC `52:54:00:xx:xx:xx`
3. Some routers/access points reject or drop packets from the "unknown" VM MAC
4. The VM fails to get a DHCP lease or gets a link-local `169.254.x.x` address

**Symptoms:**
- VM gets `169.254.x.x` (APIPA/link-local) instead of a proper LAN IP
- DHCP requests time out
- VM has no internet connectivity
- `vm status` shows no IP or shows a link-local address

### Solutions

**Option 1: Use Shared Mode**
```bash
vm start myvm --net shared
```
This always works as it uses macOS's NAT, bypassing router DHCP entirely.

**Option 2: Use Ethernet Instead of WiFi**
Wired connections don't have the MAC filtering issue. If you have a USB-C/Thunderbolt Ethernet adapter:
```bash
vm start myvm --net bridged --bridge en5  # Adjust interface name
```

**Option 3: Fix Your Router Settings**

Some routers have settings that interfere with bridged WiFi. See the router-specific section below.

---

## BT Smart Hub 2: Fixing Bridged Mode over WiFi

The **BT Smart Hub 2** (common in the UK) has a "Smart Setup" feature that causes DHCP failures for bridged VMs over WiFi.

### The Fix: Change to Mode 2

1. Open your browser and go to `http://192.168.1.254` (or your router's IP)
2. Log in with your admin password
3. Navigate to **Advanced Settings** → **Firewall** (or similar)
4. Find **Smart Setup** and change it from **Mode 1** to **Mode 2**
5. Save and wait for the router to apply changes

**Mode 2** relaxes the MAC address restrictions, allowing VMs to get proper DHCP leases.

### After the Fix

```bash
# Create and start a VM with bridged mode
vm create bridgetest
vm start bridgetest

# Should now get a proper 192.168.1.x IP
vm status bridgetest
```

**Note:** Other routers may have similar features under names like:
- "Client Isolation"
- "AP Isolation"
- "Wireless Isolation"
- "DHCP Guard"
- "MAC Filtering"

Check your router's documentation if you experience DHCP issues with bridged mode over WiFi.

---

## Best IP Selection

To avoid stale DNS/ARP issues, the toolkit merges multiple signals:

1. ARP (with MAC normalization for macOS quirks)
2. DNS fallback (A record)
3. Console log parsing (recent DHCP-assigned IPv4s)
4. SSH reachability probing (prefer reachable IPs)

This reduces false "initializing/booting" states and points SSH to a reachable address.

## Status modes

- Default: full accuracy, uses all signals
- `--fast`: skips slower checks (like DNS), no stats section
- `--basic`: PID-only; no IP/SSH probes (fastest)

## Keeping hosts in sync

Use the built-in helper to keep `/etc/hosts` aligned with the best IPs:

```bash
# Dry-run (preview)
vm hosts-sync

# Apply changes (requires sudo)
vm hosts-sync --apply

# Limit to specific VMs
vm hosts-sync --apply alpha bravo
```

After applying on macOS, flush caches:

```bash
sudo dscacheutil -flushcache && sudo killall -HUP mDNSResponder
```

## Troubleshooting stale IPs

- If `vm status` shows a different IP than SSH/tcpdump, trust the console-derived IP and run:
  - `vm hosts-sync --apply`
  - Then flush caches (commands above)
- If a clone reports failure to start, ensure the overlay has been rebased to the new base (the clone command does this automatically as of v1.2.0)

## SSH readiness

Cloud-init runcmd ensures SSH is enabled on first boot:

- Ubuntu/Debian: `systemctl enable --now ssh`
- Fedora/CentOS: `systemctl enable --now sshd`

Give cloud-init a minute to finish; `vm status` will indicate when SSH is reachable.

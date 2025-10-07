# Networking & Name Resolution

This guide explains how the toolkit finds the “best IP” for your VMs on macOS and how to keep local name resolution accurate.

## Best IP selection

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

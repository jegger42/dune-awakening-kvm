#!/usr/bin/env bash
# Read-only status: VM state, IP, host RAM (rss), battlegroup/world health.
#   Pre:  run as root.
#   Post: prints status to stdout; refreshes $STATE/vm-ip if an IP is found;
#         mutates nothing else. Safe whether the VM is up, down, or undefined.
source "$(dirname "$0")/lib.sh"; require_root
mkdir -p "$STATE"
cyan "VM:"; "${VIRSH[@]}" domstate "$VM_NAME" 2>/dev/null || echo "  (not defined)"
ip=$(find_ip || true); [ -n "$ip" ] && { echo "  IP: $ip"; echo "$ip" > "$STATE/vm-ip"; }
rss=$("${VIRSH[@]}" dommemstat "$VM_NAME" 2>/dev/null | awk '/rss/{printf "%.1f GB",$2/1048576}') || true
[ -n "$rss" ] && echo "  host RAM (rss): $rss"
cyan "battlegroup:"; ssh_vm 'battlegroup status' 2>/dev/null || echo "  (VM unreachable / not set up yet)"

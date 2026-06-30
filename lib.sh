#!/usr/bin/env bash
# Shared config + helpers for the Dune Awakening KVM launcher.
# Clean-room: this repo contains NO vendor files. You supply your own appliance
# disk (dune-server.vhdx) from your legally-obtained Steam install; it is
# gitignored and never committed.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- tunables (override via env) ---
VM_NAME="${VM_NAME:-dune-awakening}"
APPLIANCE_DIR="${APPLIANCE_DIR:-$HERE/appliance}"   # drop your *.vhdx here
QCOW="${QCOW:-/var/lib/libvirt/images/dune-server.qcow2}"
RAM_GB="${RAM_GB:-30}"        # Funcom rec: ~20 (w/ swap) .. 40. 30 = basic world.
VCPUS="${VCPUS:-8}"
DISK_GB="${DISK_GB:-100}"
DISK_BUS="${DISK_BUS:-sata}"  # sata boots most reliably under OVMF + matches the
                              # appliance's /dev/sda origin; first-run auto-detects anyway.
NET_MODE="${NET_MODE:-bridge}"   # bridge | macvtap
BRIDGE="${BRIDGE:-br0}"
NIC="${NIC:-}"
# Static IP (recommended on LANs with >1 DHCP server, to avoid the VM racing onto
# the wrong subnet). Empty = DHCP. Gateway defaults to the .1 of the IP's /24.
STATIC_IP="${STATIC_IP:-}"
STATIC_NETMASK="${STATIC_NETMASK:-255.255.255.0}"
STATIC_GW="${STATIC_GW:-}"
STATE="${STATE:-$HERE/state}"    # gitignored: ssh key, discovered IP
SSH_KEY="$STATE/id_ed25519"
VIRSH=(virsh -c qemu:///system)
SSH_OPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR)

red()  { printf '\033[31m%s\033[0m\n' "$*" >&2; }
cyan() { printf '\033[36m%s\033[0m\n' "$*"; }
die()  { red "ERROR: $*"; exit 1; }
require_root() { [ "$(id -u)" -eq 0 ] || die "run with sudo (system libvirt + image pool)"; }

# Locate the OVMF firmware, preferring a NON-secure-boot build (the appliance's
# bootloader isn't MS-signed; Secure Boot rejects it with "Access denied").
find_ovmf() {
    OVMF_CODE="${OVMF_CODE:-}"; OVMF_VARS="${OVMF_VARS:-}"
    [ -n "$OVMF_CODE" ] || for c in /usr/share/OVMF/OVMF_CODE_4M.fd /usr/share/OVMF/OVMF_CODE.fd \
        /usr/share/edk2/x64/OVMF_CODE.4m.fd /usr/share/edk2/ovmf/OVMF_CODE.fd; do
        [ -f "$c" ] && { OVMF_CODE="$c"; break; }; done
    [ -n "$OVMF_VARS" ] || for v in /usr/share/OVMF/OVMF_VARS_4M.fd /usr/share/OVMF/OVMF_VARS.fd \
        /usr/share/edk2/x64/OVMF_VARS.4m.fd /usr/share/edk2/ovmf/OVMF_VARS.fd; do
        [ -f "$v" ] && { OVMF_VARS="$v"; break; }; done
    [ -n "$OVMF_CODE" ] && [ -n "$OVMF_VARS" ] || die "non-secureboot OVMF not found (apt install ovmf)"
}

# The MAC libvirt assigned the VM's NIC.
vm_mac() { "${VIRSH[@]}" domiflist "$VM_NAME" 2>/dev/null | awk 'NR>2 && $5 ~ /:/ {print $5; exit}'; }

# Discover the VM's LAN IPv4. Bridged guests aren't in libvirt's DHCP leases, so
# use the ARP source, then fall back to the host neighbor table by MAC.
find_ip() {
    [ -n "$STATIC_IP" ] && { echo "$STATIC_IP"; return 0; }   # deterministic: skip DHCP discovery
    local ip mac
    ip=$("${VIRSH[@]}" domifaddr "$VM_NAME" --source arp 2>/dev/null \
        | awk '/ipv4/{print $4}' | cut -d/ -f1 | head -1)
    [ -n "$ip" ] && { echo "$ip"; return 0; }
    mac=$(vm_mac); [ -n "$mac" ] || return 1
    ip neigh 2>/dev/null | awk -v m="$mac" 'BEGIN{IGNORECASE=1} $0 ~ m && $1 ~ /^[0-9.]+$/{print $1; exit}'
}

# Wait up to N seconds for the VM to become reachable. With STATIC_IP, poll ping
# (the address is known; we just wait for it to come up). Else discover via DHCP.
wait_for_ip() {
    local t="${1:-180}" ip
    if [ -n "$STATIC_IP" ]; then
        cyan "waiting for VM at static $STATIC_IP to respond (up to ${t}s)..."
        for ((i=0;i<t;i+=3)); do ping -c1 -W1 "$STATIC_IP" >/dev/null 2>&1 && { echo "$STATIC_IP"; return 0; }; sleep 3; done
        return 1
    fi
    cyan "waiting for the VM to get a LAN IP (up to ${t}s)..."
    for ((i=0;i<t;i+=3)); do ip=$(find_ip || true); [ -n "$ip" ] && { echo "$ip"; return 0; }; sleep 3; done
    return 1
}

# Run a command in the VM with the appliance's bin dir on PATH. `ssh host cmd`
# uses a NON-login shell that does not read the login profile, so ~/.dune/bin
# (where `battlegroup` lives) is off PATH and the command comes back "not found".
# Prepend it explicitly -- shell-agnostic (the appliance is busybox/ash, so a
# `bash -lc` login-shell wrap is not safe to assume). $HOME/$PATH expand remotely.
ssh_vm() { ssh "${SSH_OPTS[@]}" -i "$SSH_KEY" "dune@$(cat "$STATE/vm-ip")" "PATH=\"\$HOME/.dune/bin:\$PATH\" $*"; }

#!/usr/bin/env bash
# Shared config + helpers for the Dune Awakening KVM launcher.
# Clean-room: this repo contains NO vendor files. You supply your own appliance
# disk (dune-server.vhdx) from your legally-obtained Steam install; it is
# gitignored and never committed.
#
# Module contract: this file is SOURCED, not executed.
#   Pre:  bash; sourced by a control script (launch/start/stop/status/ssh/destroy/solo).
#   Post: the tunables below and the helper functions are defined; sourcing has no
#         side effects (nothing runs until a function is called).
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

# --- tiny I/O helpers (trivial; no contract beyond the one line) ---
red()  { printf '\033[31m%s\033[0m\n' "$*" >&2; }   # red diagnostic -> stderr
cyan() { printf '\033[36m%s\033[0m\n' "$*" >&2; }   # cyan status -> stderr, so $(...) captures (e.g. IP=$(wait_for_ip)) never swallow it
die()  { red "ERROR: $*"; exit 1; }                 # Post: prints reason to stderr, exits 1 (never returns)
# require_root -- Pre: none. Post: returns 0 if EUID 0; else dies (never returns non-root).
require_root() { [ "$(id -u)" -eq 0 ] || die "run with sudo (system libvirt + image pool)"; }

# find_ovmf -- locate the OVMF firmware, preferring a NON-secure-boot build (the
# appliance's bootloader isn't MS-signed; Secure Boot rejects it "Access denied").
#   Pre:  OVMF installed (apt install ovmf); optional OVMF_CODE/OVMF_VARS overrides.
#   Post: OVMF_CODE and OVMF_VARS are set to existing files; dies if neither found.
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

# vm_mac -- the MAC libvirt assigned the VM's NIC.
#   Pre:  VM_NAME defined (the domain may or may not exist).
#   Post: echoes the NIC MAC; echoes nothing if the domain has no NIC / doesn't exist. Exit 0.
vm_mac() { "${VIRSH[@]}" domiflist "$VM_NAME" 2>/dev/null | awk 'NR>2 && $5 ~ /:/ {print $5; exit}'; }

# find_ip -- discover the VM's LAN IPv4. Bridged guests aren't in libvirt's DHCP
# leases, so use the ARP source, then fall back to the host neighbor table by MAC.
#   Pre:  VM_NAME defined; either STATIC_IP set, or the VM is up and has ARPed.
#   Post: echoes the IP and returns 0; returns 1 if none found. STATIC_IP short-circuits.
find_ip() {
    [ -n "$STATIC_IP" ] && { echo "$STATIC_IP"; return 0; }   # deterministic: skip DHCP discovery
    local ip mac
    ip=$("${VIRSH[@]}" domifaddr "$VM_NAME" --source arp 2>/dev/null \
        | awk '/ipv4/{print $4}' | cut -d/ -f1 | head -1)
    [ -n "$ip" ] && { echo "$ip"; return 0; }
    mac=$(vm_mac); [ -n "$mac" ] || return 1
    ip neigh 2>/dev/null | awk -v m="$mac" 'BEGIN{IGNORECASE=1} $0 ~ m && $1 ~ /^[0-9.]+$/{print $1; exit}'
}

# ssh_up -- is sshd accepting on <host>:22? The appliance answers ping / has an IP
# before sshd is listening, so callers gate on this, not mere reachability --
# otherwise the first key-install ssh races the boot and dies "Connection refused".
#   Pre:  $1 = host/IP.
#   Post: returns 0 if a TCP connect to :22 succeeds within ~2s; non-zero otherwise. No output.
ssh_up() { timeout 2 bash -c ": </dev/tcp/$1/22" 2>/dev/null; }

# wait_for_ip -- block until the VM is reachable AND sshd is up, up to N seconds.
# With STATIC_IP the address is known (poll the port); else discover the DHCP IP first.
#   Pre:  $1 = timeout secs (default 180); STATIC_IP set (static path) or find_ip can discover (DHCP path).
#   Post: echoes the IP and returns 0 once port 22 accepts; returns 1 on timeout. Status -> stderr.
wait_for_ip() {
    local t="${1:-180}" ip
    if [ -n "$STATIC_IP" ]; then
        cyan "waiting for VM at static $STATIC_IP (network + sshd, up to ${t}s)..."
        for ((i=0;i<t;i+=3)); do ssh_up "$STATIC_IP" && { echo "$STATIC_IP"; return 0; }; sleep 3; done
        return 1
    fi
    cyan "waiting for the VM to get a LAN IP + sshd (up to ${t}s)..."
    for ((i=0;i<t;i+=3)); do
        ip=$(find_ip || true)
        [ -n "$ip" ] && ssh_up "$ip" && { echo "$ip"; return 0; }
        sleep 3
    done
    return 1
}

# ssh_vm -- run a command in the VM with the appliance's bin dir on PATH. `ssh host
# cmd` uses a NON-login shell that does not read the login profile, so ~/.dune/bin
# (where `battlegroup` lives) is off PATH and the command comes back "not found".
# Prepend it explicitly -- shell-agnostic (the appliance is busybox/ash, so a
# `bash -lc` login-shell wrap is not safe to assume). $HOME/$PATH expand remotely.
#   Pre:  $STATE/vm-ip holds the IP; $SSH_KEY is installed in the VM; "$@" = remote command.
#   Post: runs the command over ssh as dune@<ip>; exit status + stdout are the remote command's.
ssh_vm() { ssh "${SSH_OPTS[@]}" -i "$SSH_KEY" "dune@$(cat "$STATE/vm-ip")" "PATH=\"\$HOME/.dune/bin:\$PATH\" $*"; }

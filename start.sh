#!/usr/bin/env bash
# Boot the VM (if down) and start the battlegroup.
#   Pre:  run as root; the VM was created once via launch.sh (disk + SSH key exist).
#   Post: VM running, battlegroup started, connect IP printed. Safe if already up.
source "$(dirname "$0")/lib.sh"; require_root
"${VIRSH[@]}" domstate "$VM_NAME" 2>/dev/null | grep -q running || { cyan "starting VM..."; "${VIRSH[@]}" start "$VM_NAME"; wait_for_ip 180 >/dev/null || die "VM started but never became reachable (check the bridge / boot console: virt-viewer $VM_NAME)"; }
ip=$(resolve_ip)   # establish + cache vm-ip in BOTH paths (down->up AND already-up), so ssh_vm's precondition always holds
cyan "starting battlegroup..."; ssh_vm 'battlegroup start' && cyan "up. connect in-game to: $ip"

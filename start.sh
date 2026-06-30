#!/usr/bin/env bash
# Boot the VM (if down) and start the battlegroup.
source "$(dirname "$0")/lib.sh"; require_root
"${VIRSH[@]}" domstate "$VM_NAME" 2>/dev/null | grep -q running || { cyan "starting VM..."; "${VIRSH[@]}" start "$VM_NAME"; ip=$(wait_for_ip 180) && echo "$ip" > "$STATE/vm-ip"; }
cyan "starting battlegroup..."; ssh_vm 'battlegroup start' && cyan "up. connect in-game to: $(cat "$STATE/vm-ip")"

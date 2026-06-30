#!/usr/bin/env bash
# Tear down the VM. Keeps the qcow2 (the world) unless KEEP_DISK=0.
source "$(dirname "$0")/lib.sh"; require_root
"${VIRSH[@]}" destroy "$VM_NAME" 2>/dev/null || true
"${VIRSH[@]}" undefine "$VM_NAME" --nvram 2>/dev/null || true
cyan "domain removed."
if [ "${KEEP_DISK:-1}" = 0 ]; then rm -f "$QCOW"; cyan "deleted disk $QCOW (world gone)"; else cyan "kept disk $QCOW (world preserved; re-run ./launch.sh to reattach)"; fi

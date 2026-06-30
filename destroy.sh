#!/usr/bin/env bash
# Tear down the VM. Keeps the qcow2 (the world) unless KEEP_DISK=0.
#   Pre:  run as root. Safe if the domain does not exist (all steps tolerate absence).
#   Post: the libvirt domain + its nvram are removed; the qcow2 is KEPT (world
#         preserved) unless KEEP_DISK=0, in which case the disk/world is deleted.
source "$(dirname "$0")/lib.sh"; require_root
"${VIRSH[@]}" destroy "$VM_NAME" 2>/dev/null || true
"${VIRSH[@]}" undefine "$VM_NAME" --nvram 2>/dev/null || true
cyan "domain removed."
if [ "${KEEP_DISK:-1}" = 0 ]; then rm -f "$QCOW"; cyan "deleted disk $QCOW (world gone)"; else cyan "kept disk $QCOW (world preserved; re-run ./launch.sh to reattach)"; fi

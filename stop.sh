#!/usr/bin/env bash
# Graceful: stop the battlegroup (clean DB/world save) THEN power off the VM.
#   Pre:  run as root; the VM exists (created via launch.sh). Safe if already off.
#         Best-effort on the world-flush: if the VM is unreachable (off, or no
#         cached vm-ip) the battlegroup stop is skipped and shutdown still proceeds
#         -- deliberately NOT routed through resolve_ip, which would die and block
#         the shutdown.
#   Post: battlegroup stopped (world flushed) when reachable; VM shutdown requested
#         either way. A failed battlegroup stop is reported, not fatal.
source "$(dirname "$0")/lib.sh"; require_root
cyan "stopping battlegroup (lets the world/db flush)..."; ssh_vm 'battlegroup stop' || red "battlegroup stop failed (continuing to VM shutdown)"
cyan "shutting down VM..."; "${VIRSH[@]}" shutdown "$VM_NAME"
cyan "done. (force-off if it hangs: ${VIRSH[*]} destroy $VM_NAME)"

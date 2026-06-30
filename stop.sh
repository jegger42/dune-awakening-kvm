#!/usr/bin/env bash
# Graceful: stop the battlegroup (clean DB/world save) THEN power off the VM.
#   Pre:  run as root; the VM exists (created via launch.sh). Safe if already off.
#   Post: battlegroup stopped (world flushed), VM shutdown requested. A failed
#         battlegroup stop is reported but does not block the VM shutdown.
source "$(dirname "$0")/lib.sh"; require_root
cyan "stopping battlegroup (lets the world/db flush)..."; ssh_vm 'battlegroup stop' || red "battlegroup stop failed (continuing to VM shutdown)"
cyan "shutting down VM..."; "${VIRSH[@]}" shutdown "$VM_NAME"
cyan "done. (force-off if it hangs: ${VIRSH[*]} destroy $VM_NAME)"

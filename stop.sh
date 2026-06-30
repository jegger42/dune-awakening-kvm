#!/usr/bin/env bash
# Graceful: stop the battlegroup (clean DB/world save) THEN power off the VM.
source "$(dirname "$0")/lib.sh"; require_root
cyan "stopping battlegroup (lets the world/db flush)..."; ssh_vm 'battlegroup stop' || red "battlegroup stop failed (continuing to VM shutdown)"
cyan "shutting down VM..."; "${VIRSH[@]}" shutdown "$VM_NAME"
cyan "done. (force-off if it hangs: ${VIRSH[*]} destroy $VM_NAME)"

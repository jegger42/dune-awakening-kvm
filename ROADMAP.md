# Roadmap

Possible improvements. The current launcher works; none of these are blocking.

## Skip the vhdx -> qcow2 conversion (qcow2 overlay)  [near-term, easy win]

`launch.sh` currently does a full `qemu-img convert vhdx -> qcow2` plus a resize,
which copies the entire disk. QEMU supports `vhdx` as a disk format directly, so a
qcow2 **overlay backed by the vhdx** should get the same result without the copy:

```
qemu-img create -f qcow2 -b dune-server.vhdx -F vhdx -o size=100G overlay.qcow2
```

Benefits: near-instant (no full conversion), the original vendor `.vhdx` stays
pristine (copy-on-write, never mutated), still gives the 100G virtual size the
first-run grows into, and keeps qcow2 snapshots.

Verify before adopting:
- the installed QEMU accepts a non-qcow2 (`vhdx`) backing format;
- the first-run's `growpart` / `pvresize` / `lvextend` behave correctly against an overlay;
- `destroy.sh` and world-preservation still hold (the world now lives in the
  overlay; keep that, the vhdx is the immutable base).

Source: suggested by a commenter (wadrasil) on the r/duneawakening launch thread, 2026-06-30.

## Reclaim qcow2 disk slack (discard/TRIM + sparsify)  [near-term, easy win]

qcow2 grows but never shrinks on its own: blocks freed inside the guest (game
patches replacing depot chunks, logs, swap pages, container image churn) stay
allocated in the host image. `launch.sh`'s `virt-install` disk line does not set
`discard=unmap`, so guest TRIM is never passed through, and the image only ever
grows. An older, patched world drifts well above its true footprint (observed:
35G vs a fresh 21G for the same server payload).

Two parts:
- **Forward fix:** add `discard=unmap` to the `--disk` line in `launch.sh` so guest
  `fstrim -av` (or periodic `fstrim.timer`) punches freed blocks back to holes.
  Confirm the chosen bus passes discard (virtio-scsi does cleanly; for `sata`
  verify libata TRIM reaches the qcow2).
- **One-time cleanup of an existing image:** with the VM down,
  `virt-sparsify --in-place /var/lib/libvirt/images/dune-server.qcow2` reclaims the
  current slack.

Verify before adopting: discard does not interact badly with the first-run
`growpart`/`lvextend` LVM layout, and snapshots (if any) are accounted for
(`--in-place` sparsify and snapshots do not mix).

## Container-native: run the UE5 server directly  [longer-term, larger lift, maybe]

The appliance is a UE5 dedicated server under an embedded k3s/Alpine stack. A
container-native path -- extract and run the server directly, as CubeCoders' AMP
does -- would be lighter than booting the whole appliance and would sidestep the
embedded-k3s surface. It is a much larger effort and brittle to vendor image
changes (re-extract each update), so this is a "maybe," not a commitment. Booting
the appliance as-shipped is the low-maintenance default on purpose: drop in a new
`.vhdx`, re-run, done.

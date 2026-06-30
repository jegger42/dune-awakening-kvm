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

## Container-native: run the UE5 server directly  [longer-term, larger lift, maybe]

The appliance is a UE5 dedicated server under an embedded k3s/Alpine stack. A
container-native path -- extract and run the server directly, as CubeCoders' AMP
does -- would be lighter than booting the whole appliance and would sidestep the
embedded-k3s surface. It is a much larger effort and brittle to vendor image
changes (re-extract each update), so this is a "maybe," not a commitment. Booting
the appliance as-shipped is the low-maintenance default on purpose: drop in a new
`.vhdx`, re-run, done.

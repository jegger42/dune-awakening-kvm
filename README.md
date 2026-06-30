# dune-awakening-kvm

Run the **Dune: Awakening self-hosted server** on Linux/KVM instead of
Windows+Hyper-V. Drop in your appliance disk, run one command, get a running
world on a bridged LAN VM.

> **No vendor files are included.** This repo is independent automation. You
> supply your own `dune-server.vhdx` (from your legally-obtained Steam install of
> the official Self-Hosted Server). The launcher only *drives tools already inside
> your appliance* (its bundled `steamcmd`, its own `setup.sh`). Nothing
> proprietary is redistributed, and nothing here defeats licensing or auth -- the
> server still authenticates to FunCom with your own self-hosting token.
>
> *Not affiliated with or endorsed by Funcom. "Dune: Awakening" and related names
> are trademarks of their respective owners, used here only to describe what this
> tool interoperates with.*

## Alternatives

Want a managed control panel or a lighter, container-native setup? Use
**[AMP by CubeCoders](https://cubecoders.com/AMP/Dune)**, which now runs the Dune:
Awakening server on normal Linux with **no Hyper-V or VM at all** -- it extracts the
underlying server and runs it directly under Docker/Podman. It is the more polished,
fuller-featured option, and the right pick if you want a panel or the lightest footprint.

This launcher takes the opposite tradeoff on purpose: it boots Funcom's shipped
appliance **as-is** under KVM instead of re-packaging it. That keeps it a single,
dependency-light script with near-zero maintenance and robustness to vendor updates
(drop in a new `.vhdx`, re-run, done), at the cost of running the heavier appliance
stack (the embedded k3s and friends). Pick this if you want a free, no-panel launcher
that runs the exact vendor-supported image; pick AMP if you want a managed panel or
the smallest footprint.

## Requirements

- A 64-bit x86 CPU with **AVX2** (the server binary needs it; the VM uses host-CPU
  passthrough to expose it).
- **Hardware virtualization** (Intel VT-x / AMD-V) enabled in BIOS/UEFI.
- **~100 GB of free disk** for the VM's world disk (a sparse qcow2 that grows with
  the world), plus room for the ~1 GB appliance image.
- **RAM:** Funcom's baseline is ~**20 GB**, scaling with how many maps/servers the
  battlegroup runs. This launcher defaults to 30 GB for headroom; set `RAM_GB` lower
  on smaller hosts (e.g. `sudo RAM_GB=16 ./launch.sh`), and below 20 GB enable the
  server's experimental swap (see [Settings](#settings)). Trimming maps is the
  biggest RAM lever.
- **OS:** tested on **Ubuntu 24.04**. Other distros work if you install the
  equivalent packages and create a bridge your own way.
- A Windows machine (or Windows VM) **once**, to generate the appliance disk (below).

## Quickstart

1. **Get your appliance disk** (one-time, on Windows) and copy the `.vhdx` to this
   host -- see [Get your appliance disk](#get-your-appliance-disk).
2. **Set up the host** (packages + a network bridge) -- see [Host setup](#host-setup).
3. **Drop the disk and launch:**
   ```
   cp /path/to/your-server.vhdx appliance/
   sudo ./launch.sh                 # or: sudo RAM_GB=16 ./launch.sh
   ```
   Follow the interactive first-run: pick **PRIVATE/LAN**, then your world name,
   region, and **FLS token** (from account.duneawakening.com).
4. **Start the world:**
   ```
   sudo ./start.sh                  # prints the IP to connect to
   ```
5. **Join in-game** -- see [Connect from the game](#connect-from-the-game).

## Get your appliance disk

This repo ships no vendor files; you provide the disk from your own copy of the
official server. Funcom's official guide is the authoritative source for the
Windows install, the FLS token, and networking:
**<https://duneawakening.com/self-hosted-servers/>**. The short version for getting
the disk onto Linux:

1. On a **Windows** machine, install the **Dune: Awakening Self-Hosted Server**
   from Steam. It builds a Hyper-V virtual machine.
2. The disk image lands in the **`Virtual Hard Disks`** folder under the server's
   Steam install folder (a `.vhdx` file).
3. Copy that `.vhdx` to your Linux host and drop it in `appliance/`. The launcher
   picks up any `*.vhdx` it finds there, so the filename does not matter.

You only need Windows for this one step; everything after runs on Linux.

## Host setup

One-time, on the Linux host.

**Packages** (Ubuntu/Debian; install the equivalents on other distros):
```
sudo apt install qemu-utils libvirt-daemon-system virtinst ovmf libguestfs-tools openssh-client
sudo usermod -aG libvirt,kvm "$USER"     # re-login after
```

**A LAN path for the VM.** Either a **bridge** (recommended -- the VM gets a real
LAN IP and the host can reach it) or **macvtap** (no host network change, but the
host cannot talk to the VM directly).

Bridge via netplan (`/etc/netplan/01-br0.yaml`, swap `enp7s0` for your NIC):
```yaml
network:
  version: 2
  renderer: networkd
  ethernets: {enp7s0: {dhcp4: no}}
  bridges:
    br0: {interfaces: [enp7s0], dhcp4: yes, parameters: {stp: false, forward-delay: 0}}
```
`sudo netplan apply` (at the console -- the link blips). Not on netplan
(Fedora/Arch/NetworkManager)? Create a bridge named `br0` however your distro does
it, or skip the bridge and use `NET_MODE=macvtap` (see below).

## Run it

```
# launch (defaults: 30G RAM, 8 vCPU, 100G disk, bridge br0, sata bus)
sudo ./launch.sh

# examples:
sudo RAM_GB=20 ./launch.sh
sudo STATIC_IP=10.0.0.50 ./launch.sh          # pin a static IP (recommended if your LAN has >1 DHCP server)
sudo -E NET_MODE=macvtap NIC=enp7s0 ./launch.sh
```

`launch.sh` converts the disk, defines and boots the VM, then runs the interactive
first-run. The first run downloads the server payload via the appliance's own
steamcmd, so it can take several minutes -- that is normal, not a hang. When
prompted: pick **PRIVATE/LAN** for the battlegroup IP, then enter your world name,
region, and **FLS token** (account.duneawakening.com).

After setup, day to day:
```
sudo ./start.sh     # boot VM (if down) + start the battlegroup; prints the IP to connect to
sudo ./status.sh    # VM state, IP, host RAM, battlegroup/map status
sudo ./stop.sh      # graceful: battlegroup stop (clean save) -> VM shutdown
sudo ./ssh.sh       # shell in the VM   (or: sudo ./ssh.sh battlegroup edit)
sudo ./destroy.sh   # remove the VM (keeps the world disk; KEEP_DISK=0 to wipe)
```

## Connect from the game

Once `./start.sh` reports the world is up, launch Dune: Awakening, open the
**Experimental** server tab, and search for the **world name you set during setup**.

- **All players on the same LAN:** nothing else to do, no port forwarding needed.
- **Players over the internet:** forward these ports on your router to the VM's IP
  (use a pinned `STATIC_IP` so it does not move):
  - **7777-7810 UDP** -- the game servers
  - **31982 TCP** -- RMQ (the server's message broker)

  These follow Funcom's [official self-hosted-server instructions](https://duneawakening.com/self-hosted-servers/). The starting ports are configurable on the server (the `Port` / `IGWPort` options); if you change them, adjust your forwarding to match.

## Security

The threat model in one place. The appliance itself is Funcom's; this covers how the
launcher runs it:

- **A unique SSH key per install.** `launch.sh` generates a fresh `ed25519` keypair
  and installs it, so there is no shared key baked across deployments. (Funcom's
  appliance still ships a default `dune` account password, used once to install the
  key, so do not expose the VM's SSH to the internet.)
- **LAN-only by default.** Bridge mode gives the VM a real *LAN* IP, not a public one.
  The server is reachable only from your own network unless you deliberately
  port-forward on your router.
- **Minimal exposure if you go remote.** Forward only the game ports
  (`7777-7810/udp` + `31982/tcp`), never the whole VM and never SSH. See
  [Connect from the game](#connect-from-the-game).
- **The appliance internals are Funcom's** (the embedded k3s, bundled services). This
  launcher runs the image as shipped; it does not harden those internals, so keep the
  VM network-isolated. For extra isolation run `NET_MODE=macvtap`, or put the bridge
  on a separate VLAN so the VM cannot reach the rest of your network.

Short version: unique key, LAN-only by default, minimal ports if remote. Hardening the
server beyond the network boundary is a Funcom-image concern, not something a launcher
can fix, so run it isolated.

## Settings

- **World / maps / scaling:** `sudo ./ssh.sh battlegroup edit` (TUI). Trimming maps
  is the biggest RAM lever -- drop Deep Desert / story / social maps for a small world.
- **Gameplay rules:** `UserGame.ini` / `UserEngine.ini` in
  `~/.dune/download/scripts/setup/config/` inside the VM, then `battlegroup apply-default-usersettings`.
- **VM RAM/CPU:** re-run `sudo RAM_GB=N ./launch.sh` (reuses the world disk), or
  `sudo virsh -c qemu:///system edit dune-awakening`. Below 20G: run
  `battlegroup enable-experimental-swap` in the VM.

## What it does (under the hood)

Convert `vhdx -> qcow2` -> resize to 100G -> define a KVM VM (UEFI **Secure Boot
off**, host-CPU passthrough for AVX2, bridged LAN) -> boot -> install an SSH key ->
run a clean-room first-run inside the VM (grow disk, persist DHCP, pull the vendor
payload via the appliance's anonymous `steamcmd`, hand off to the vendor's
`setup.sh` for world creation). Every gotcha from doing this by hand is baked in.

### Gotchas it handles for you
- **Secure Boot off** -- the appliance's loader isn't MS-signed; SB firmware rejects it ("Access denied").
- **UEFI/Gen2 boot** -- uses OVMF; that's why a plain BIOS boot fails.
- **Docker vs bridge** -- Docker's `br_netfilter` + FORWARD DROP eats the VM's DHCP; the launcher disables bridge netfilter (and persists it).
- **Disk auto-grow** -- appliance ships a ~1GB root on a sparse disk; first-run grows the LVM into 100G, bus-agnostic (`/dev/sda` or `/dev/vda`).
- **DHCP persistence** -- writes `/etc/network/interfaces` so the IP survives reboots.
- **No sftp** -- the appliance lacks `sftp-server`, so files go in via `ssh 'cat >'`, not `scp`.
- **Bridge IP discovery** -- bridged guests aren't in libvirt's leases; IP is found via ARP / neighbor table.
- **`battlegroup` over ssh** -- the appliance only puts `battlegroup` (`~/.dune/bin`) on PATH in a *login* shell. The control scripts prepend `~/.dune/bin` to PATH on every remote command so it always resolves.

### Notes
- `sata` disk bus is the default (most reliable UEFI boot; matches the appliance's
  `/dev/sda` origin). `DISK_BUS=virtio` is faster but if it won't boot, that's why.
- The world lives on the qcow2, independent of the VM definition -- `destroy.sh`
  keeps it by default; reboots and re-launches preserve it.
- This is for a server you own and are entitled to run. It changes the *host*, not
  the game.

## Troubleshooting

- **`launch.sh` exits with "VM never got a LAN IP".** The VM booted but never
  reached the network. Usual causes: the bridge `br0` does not exist or is on the
  wrong NIC (check `ip link`), a second DHCP server on the LAN (pin one with
  `STATIC_IP=...`), or Docker's FORWARD policy eating bridged DHCP (the launcher
  disables this, but a later Docker restart can re-impose it). Quick alternative:
  `sudo -E NET_MODE=macvtap NIC=<your-nic> ./launch.sh`.
- **VM won't boot / black screen** (watch with `virt-viewer dune-awakening`).
  Secure Boot must be **off** (handled by the launcher) and the disk bus matters:
  the default `sata` is the most reliable; if you forced `DISK_BUS=virtio` and it
  won't boot, that's why. Also confirm AVX2 + virtualization are available on the host.
- **`./status.sh` shows the VM `running` + reachable, but the battlegroup line
  drops to a `dune@<ip> password:` prompt then "(VM unreachable)".** The SSH key
  `state/id_ed25519` is missing (it lives only in gitignored `state/`, so a
  `git clean -dfx` or manual cleanup wipes it). The VM is fine. Re-key it (the
  appliance's default password is `dune`):
  ```
  sudo ssh-keygen -t ed25519 -N '' -f state/id_ed25519 -C dune-kvm
  sudo ssh-copy-id -i state/id_ed25519.pub -o StrictHostKeyChecking=no dune@<vm-ip>
  ```
  The world disk keeps the VM's `authorized_keys`, so restoring the private key is
  all that is needed.
- **`battlegroup: command not found` when run over ssh.** Handled by the control
  scripts (see the gotcha above). If you ssh by hand, prepend
  `PATH="$HOME/.dune/bin:$PATH"` to the command.

## Contributing & License

Issues and pull requests welcome, especially additional host/distro gotchas and
non-bridge networking setups. This is independent automation: it ships no vendor
files and defeats no licensing or authentication. It only drives tools already
inside an appliance you supply, for a server you are entitled to run.

Licensed under the MIT License. See [LICENSE](LICENSE).

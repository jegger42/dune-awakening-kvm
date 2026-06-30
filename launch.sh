#!/usr/bin/env bash
# launch.sh -- drop a dune-server.vhdx in appliance/, run this, get a running
# Dune Awakening server on KVM. Convert -> resize -> define (UEFI no-secureboot,
# host-CPU, bridged) -> boot -> install ssh key -> run first-run (disk grow,
# steam payload pull, vendor world setup). One command, host-side, as root.
#   Pre:  run as root; a *.vhdx in $APPLIANCE_DIR (or VHDX=path); the host tools
#         in the preflight list installed; a usable bridge ($BRIDGE) or macvtap
#         NIC; no existing libvirt domain named $VM_NAME.
#   Post: a running, network-reachable VM with the SSH key installed and the
#         interactive first-run completed (world created). $STATE/vm-ip holds the
#         IP. Idempotent on the qcow2 (prompts to reuse an existing disk/world);
#         dies with a friendly reason on any unmet precondition.
source "$(dirname "$0")/lib.sh"
require_root

# --- preflight ---
for t in qemu-img virt-install virsh virt-customize ssh ssh-keygen; do
    command -v "$t" >/dev/null 2>&1 || die "missing '$t'. apt install qemu-utils libvirt-daemon-system virtinst ovmf libguestfs-tools openssh-client"
done
find_ovmf
mkdir -p "$STATE"

if [ -z "${VHDX:-}" ]; then
    VHDX=$(ls "$APPLIANCE_DIR"/*.vhdx 2>/dev/null | head -1) || true   # || true: don't let set -e eat the friendly error below
fi
[ -n "${VHDX:-}" ] && [ -f "$VHDX" ] || die "no .vhdx in $APPLIANCE_DIR -- drop your dune-server.vhdx there first"
cyan "appliance disk: $VHDX"

if "${VIRSH[@]}" dominfo "$VM_NAME" >/dev/null 2>&1; then
    die "domain '$VM_NAME' already exists. ./destroy.sh first, or VM_NAME=other ./launch.sh"
fi

# --- network preflight ---
case "$NET_MODE" in
    bridge)
        ip link show "$BRIDGE" >/dev/null 2>&1 || die \
"bridge '$BRIDGE' not found. Create one on your LAN NIC (see README), or:
   NET_MODE=macvtap NIC=<your-nic> sudo -E ./launch.sh"
        NET_ARG="bridge=$BRIDGE,model=virtio"; cyan "network: bridge $BRIDGE (LAN DHCP)";;
    macvtap)
        [ -n "$NIC" ] || NIC=$(ip -o route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++)if($i=="dev"){print $(i+1);exit}}')
        ip link show "$NIC" >/dev/null 2>&1 || die "set NIC=<physical interface> for macvtap"
        NET_ARG="type=direct,source=$NIC,source_mode=bridge,model=virtio"
        cyan "network: macvtap on $NIC (host<->VM can't talk; setup runs over the VM's LAN IP from this script)";;
    *) die "NET_MODE must be bridge or macvtap";;
esac

# --- Docker/bridge netfilter fix: bridged guest DHCP is dropped by Docker's
#     FORWARD policy when br_netfilter is on. Make the bridge a pure L2 switch. ---
if [ -e /proc/sys/net/bridge/bridge-nf-call-iptables ] \
   && [ "$(cat /proc/sys/net/bridge/bridge-nf-call-iptables)" != 0 ]; then
    cyan "disabling bridge netfilter (fixes Docker dropping the VM's DHCP)..."
    sysctl -w net.bridge.bridge-nf-call-iptables=0 >/dev/null
    sysctl -w net.bridge.bridge-nf-call-ip6tables=0 >/dev/null 2>&1 || true
    printf 'net.bridge.bridge-nf-call-iptables=0\nnet.bridge.bridge-nf-call-ip6tables=0\n' \
        > /etc/sysctl.d/99-dune-kvm-bridge.conf
fi

# --- convert + resize ---
if [ -f "$QCOW" ]; then
    read -r -p "$QCOW exists. Reuse it (keep the existing world)? [Y/n] " a
    [ "${a,,}" = n ] && { rm -f "$QCOW"; } || cyan "reusing existing qcow2"
fi
if [ ! -f "$QCOW" ]; then
    mkdir -p "$(dirname "$QCOW")"
    cyan "converting vhdx -> qcow2 ..."; qemu-img convert -p -f vhdx -O qcow2 "$VHDX" "$QCOW"
    cyan "resizing to ${DISK_GB}G ..."; qemu-img resize "$QCOW" "${DISK_GB}G"
    chown libvirt-qemu:kvm "$QCOW" 2>/dev/null || true
fi

# Pre-seed eth0 networking into the image (offline). A fresh appliance doesn't
# bring up eth0 on its own, so without this it never gets a LAN IP and we can't
# SSH in to run first-run -- the chicken-and-egg. Done offline so first boot is
# reachable with no console hand-holding. Idempotent; safe on reuse too.
# base64 so newlines/quoting survive the virt-customize --run-command shell.
if [ -n "$STATIC_IP" ]; then
    GW="${STATIC_GW:-$(echo "$STATIC_IP" | sed -E 's/\.[0-9]+$/.1/')}"
    cyan "pre-seeding STATIC IP $STATIC_IP (netmask $STATIC_NETMASK, gw $GW)..."
    IFACES=$(printf 'auto lo\niface lo inet loopback\n\nauto eth0\niface eth0 inet static\n    address %s\n    netmask %s\n    gateway %s\n' "$STATIC_IP" "$STATIC_NETMASK" "$GW")
else
    cyan "pre-seeding eth0 DHCP config into the image..."
    IFACES=$(printf 'auto lo\niface lo inet loopback\n\nauto eth0\niface eth0 inet dhcp\n')
fi
B64=$(printf '%s' "$IFACES" | base64 -w0)
virt-customize -a "$QCOW" --run-command "echo $B64 | base64 -d > /etc/network/interfaces" \
    || die "virt-customize failed to pre-seed networking (is libguestfs-tools installed?)"

# --- define + boot (UEFI, Secure Boot OFF, host-CPU for AVX2) ---
cyan "defining + starting '$VM_NAME' (${RAM_GB}G RAM, ${VCPUS} vCPU, $DISK_BUS disk)..."
virt-install --connect qemu:///system --name "$VM_NAME" \
    --memory "$((RAM_GB*1024))" --vcpus "$VCPUS" \
    --cpu host-passthrough --machine q35 \
    --boot "loader=$OVMF_CODE,loader.readonly=yes,loader.type=pflash,loader.secure=no,nvram.template=$OVMF_VARS" \
    --import --disk "path=$QCOW,format=qcow2,bus=$DISK_BUS" \
    --network "$NET_ARG" --osinfo detect=on,require=off \
    --graphics vnc,listen=127.0.0.1 --console pty,target_type=serial --noautoconsole

# --- find IP ---
IP=$(wait_for_ip 240) || die "VM never got a LAN IP. Check the bridge, or watch boot: virt-viewer $VM_NAME (UEFI no-boot => try DISK_BUS=sata)"
echo "$IP" > "$STATE/vm-ip"; cyan "VM IP: $IP"

# --- install ssh key (one 'dune' password prompt), then push + run first-run ---
[ -f "$SSH_KEY" ] || ssh-keygen -t ed25519 -N '' -f "$SSH_KEY" -C dune-kvm >/dev/null
cyan "installing SSH key -- enter the appliance's default password when asked:  dune"
PUB=$(cat "$SSH_KEY.pub")
ssh "${SSH_OPTS[@]}" "dune@$IP" \
    "mkdir -p ~/.ssh && chmod 700 ~/.ssh && grep -qxF '$PUB' ~/.ssh/authorized_keys 2>/dev/null || echo '$PUB' >> ~/.ssh/authorized_keys; chmod 600 ~/.ssh/authorized_keys"

cyan "uploading first-run (cat-pipe; the appliance has no sftp for scp)..."
ssh "${SSH_OPTS[@]}" -i "$SSH_KEY" "dune@$IP" 'cat > /tmp/first-run.sh && chmod +x /tmp/first-run.sh' < "$HERE/vm/first-run.sh"

cyan "running first-time setup (interactive: pick PRIVATE/LAN IP, world name/region, FLS token)..."
ssh -t "${SSH_OPTS[@]}" -i "$SSH_KEY" "dune@$IP" '/tmp/first-run.sh'

cyan ""
cyan "Setup done. Start the world:   ./start.sh        (then in-game, connect to $IP)"
cyan "Other: ./status.sh  ./stop.sh  ./ssh.sh  ./destroy.sh"

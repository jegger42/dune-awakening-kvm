#!/bin/sh
# first-run.sh -- in-VM first-boot orchestration. Runs INSIDE the appliance.
#
# Clean-room: contains no vendor code. It (1) grows the disk, (2) persists DHCP,
# then drives tools ALREADY PRESENT in the user's appliance -- the bundled
# steamcmd (anonymous, no account) to fetch the vendor payload, and the vendor's
# own setup.sh for the interactive world creation. Nothing here redistributes
# vendor content.
set -e
APP_ID=4754530
DL=/home/dune/.dune/download

echo "== [1/4] grow root volume into the resized virtual disk =="
# Bus-agnostic: find the LVM PV (works whether the disk is /dev/sda or /dev/vda).
PV=$(sudo pvs --noheadings -o pv_name 2>/dev/null | tr -d ' ' | head -1)
avail=$(df -P -B1G / | awk 'NR==2{print $4+0}')
if [ -n "$PV" ] && [ "$avail" -lt 30 ]; then
    DISK=$(echo "$PV" | sed -E 's/p?[0-9]+$//')      # /dev/sda2->/dev/sda, /dev/nvme0n1p2->/dev/nvme0n1
    PART=$(echo "$PV" | grep -oE '[0-9]+$')
    LV=$(sudo lvs --noheadings -o vg_name,lv_name 2>/dev/null | awk 'NR==1{print "/dev/"$1"/"$2}' | tr -d ' ')
    echo "   growing $DISK part $PART -> $LV"
    sudo growpart "$DISK" "$PART" || true
    sudo pvresize "$PV"
    sudo lvextend -l +100%FREE "$LV" || true
    sudo resize2fs "$LV" || true
else
    echo "   skip (already $(echo "$avail")G free)"
fi

echo "== [2/4] persist DHCP on eth0 (so the IP survives reboots) =="
if ! grep -q 'iface eth0 inet dhcp' /etc/network/interfaces 2>/dev/null; then
    printf 'auto lo\niface lo inet loopback\n\nauto eth0\niface eth0 inet dhcp\n' \
        | sudo tee /etc/network/interfaces >/dev/null
    echo "   wrote /etc/network/interfaces"
else
    echo "   already configured"
fi

echo "== [3/4] fetch the vendor payload via the appliance's own steamcmd (anonymous) =="
if [ ! -f "$DL/scripts/setup.sh" ]; then
    steamcmd +set_spew_level 1 1 +force_install_dir "$DL" +login anonymous +app_update "$APP_ID" +logoff +quit
fi
[ -f "$DL/scripts/setup.sh" ] || { echo "ERROR: payload setup.sh missing after steam download"; exit 1; }

echo "== [4/4] vendor world setup (interactive) =="
echo "   When prompted: battlegroup IP -> PRIVATE/LAN; then world name, region, and your FLS token."
exec "$DL/scripts/setup.sh"

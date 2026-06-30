#!/usr/bin/env bash
# Open a shell in the VM (or run a battlegroup command: ./ssh.sh battlegroup status)
source "$(dirname "$0")/lib.sh"; require_root
ip=$(find_ip || cat "$STATE/vm-ip" 2>/dev/null) || die "VM IP unknown (is it running?)"
echo "$ip" > "$STATE/vm-ip"
# With a command: prepend ~/.dune/bin to PATH (non-login shell skips the profile,
# so `battlegroup` would be "not found"). No args: a normal interactive login
# shell, which loads the profile itself, so leave it bare.
if [ "$#" -gt 0 ]; then ssh -t "${SSH_OPTS[@]}" -i "$SSH_KEY" "dune@$ip" "PATH=\"\$HOME/.dune/bin:\$PATH\" $*"; else ssh -t "${SSH_OPTS[@]}" -i "$SSH_KEY" "dune@$ip"; fi

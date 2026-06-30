#!/usr/bin/env bash
# Open a shell in the VM (or run a battlegroup command: ./ssh.sh battlegroup status)
#   Pre:  run as root; the VM is up and the SSH key is installed (via launch.sh).
#   Post: with args, runs them in the VM and exits with their status; with no
#         args, hands over an interactive login shell. Refreshes $STATE/vm-ip.
source "$(dirname "$0")/lib.sh"; require_root
ip=$(resolve_ip)   # find_ip -> cached vm-ip -> die; also (re)writes $STATE/vm-ip
# With a command: prepend ~/.dune/bin to PATH (non-login shell skips the profile,
# so `battlegroup` would be "not found"). No args: a normal interactive login
# shell, which loads the profile itself, so leave it bare.
if [ "$#" -gt 0 ]; then ssh -t "${SSH_OPTS[@]}" -i "$SSH_KEY" "dune@$ip" "PATH=\"\$HOME/.dune/bin:\$PATH\" $*"; else ssh -t "${SSH_OPTS[@]}" -i "$SSH_KEY" "dune@$ip"; fi

#!/usr/bin/env bash
# From the owner's PC (Git Bash), in the repo: builds the Linux server and
# installs or updates it on the server. The address is never in the repo:
#   server/deploy.sh root@<server address> [--no-build]
set -euo pipefail
host=${1:?usage: server/deploy.sh root@<server address> [--no-build]}
here=$(cd "$(dirname "$0")" && pwd)
godot=${GODOT:-/c/Users/treym/OneDrive/Desktop/Tools/Godot_v4.7.2-stable_win64_console.exe}
key=${KEY:-$HOME/.ssh/clmr_oracle}
bin="$here/../godot/build/linux-server/clmr_server.x86_64"
if [ "${2:-}" != "--no-build" ]; then
	mkdir -p "$(dirname "$bin")"
	"$godot" --headless --path "$here/../godot" --export-release "Linux Server" "$bin" >/dev/null
fi
ssh -i "$key" "$host" "mkdir -p /tmp/clmr"
scp -i "$key" -q "$bin" "$here/lobbies.json" "$here/clmr-lobbies.service" "$here/setup.sh" "$host:/tmp/clmr/"
ssh -i "$key" "$host" "bash /tmp/clmr/setup.sh"

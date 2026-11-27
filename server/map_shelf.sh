#!/usr/bin/env bash
# From the owner's PC (Git Bash), in the repo: the lobby server's MAP SHELF
# (players' maps, src/net/map_shelf.gd; it lives in /opt/clmr/maps there).
#   server/map_shelf.sh root@<server address> list              # every map, newest first
#   server/map_shelf.sh root@<server address> remove 7KQ2-M9XD  # off the shelf for good
#   server/map_shelf.sh root@<server address> backup            # the shelf to maps-<date>.tgz here
# remove asks the running server (it reads remove.txt within 10 seconds,
# deletes the map and keeps it from being put up again) and shows its log.
set -euo pipefail
usage="usage: server/map_shelf.sh root@<server address> list | remove <code> | backup"
host=${1:?$usage}
what=${2:?$usage}
key=${KEY:-$HOME/.ssh/clmr_oracle}
dir=/opt/clmr/maps
case "$what" in
list)
	ssh -i "$key" "$host" "cat $dir/list.txt 2>/dev/null || echo 'no shelf yet: nothing put up since the server got it'"
	;;
remove)
	# Only the code's letters go to the server (nothing typed reaches its shell).
	code=$(printf '%s' "${3:?$usage}" | tr 'a-z' 'A-Z' | tr -cd '0-9A-Z')
	if [ ${#code} -ne 8 ]; then
		echo "a shelf code is 8 letters, like 7KQ2-M9XD"
		exit 1
	fi
	ssh -i "$key" "$host" "echo $code >> $dir/remove.txt && chown clmr:clmr $dir/remove.txt"
	echo "asked the shelf to take $code off; its log in a moment:"
	sleep 12
	ssh -i "$key" "$host" "journalctl -u clmr-lobbies --since '-2 min' --no-pager | grep 'SHELF:' | tail -5"
	;;
backup)
	out="maps-$(date +%Y%m%d-%H%M).tgz"
	ssh -i "$key" "$host" "tar czf - -C /opt/clmr maps" > "$out"
	echo "the shelf is in $out"
	;;
*)
	echo "$usage"
	exit 1
	;;
esac

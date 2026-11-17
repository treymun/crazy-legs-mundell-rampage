#!/usr/bin/env bash
# Many balance runs (tools/balance.gd) spread over the PC, each Godot process
# with its own scratch APPDATA and LOCALAPPDATA (the boss checkpoint lives in
# the cache folder), then the report.
#
#   godot/tools/balance_runs.sh <out dir> [jobs=6] [diffs="0 1 2 3"] [skills="0 1 2"]
#       [seeds="1 2 3"] [county_seeds="1 2 3"] [chapters=a,b]
#
# Run from the repo root. GODOT may point at the Godot binary. Started again
# with the same arguments it goes on where it stopped. Each Godot process
# takes about 400 MB: mind the PC's memory when picking jobs.
set -u
out=${1:?out dir}
shift
jobs=6
diffs="0 1 2 3"
skills="0 1 2"
seeds="1 2 3"
county_seeds="1 2 3"
chapters=""
for arg in "$@"; do
	case $arg in
		jobs=*) jobs=${arg#jobs=} ;;
		diffs=*) diffs=${arg#diffs=} ;;
		skills=*) skills=${arg#skills=} ;;
		seeds=*) seeds=${arg#seeds=} ;;
		county_seeds=*) county_seeds=${arg#county_seeds=} ;;
		chapters=*) chapters=$arg ;;
	esac
done
godot=${GODOT:-/c/Users/treym/OneDrive/Desktop/Tools/Godot_v4.7.2-stable_win64_console.exe}
mkdir -p "$out/profiles"
tasks=()
for d in $diffs; do
	for k in $skills; do
		for s in $seeds; do
			# Every third run goes without the hound, to see what BLUE is worth.
			h=$(( (s + k) % 3 == 0 ? 0 : 1 ))
			tasks+=("run diff=$d skill=$k seed=$s hound=$h $chapters out=$out/c_${d}_${k}_${s}.jsonl")
		done
	done
	for s in $county_seeds; do
		tasks+=("county diff=$d seed=$s cap=900 out=$out/county_${d}_${s}.jsonl")
	done
done
n=0
running=0
for t in "${tasks[@]}"; do
	n=$((n + 1))
	prof="$out/profiles/p$n"
	mkdir -p "$prof"
	# Done before (a run stopped and started again): kept; half done: again.
	file=${t##*out=}
	if grep -q "BALANCE RUN DONE" "$prof/log.txt" 2>/dev/null; then
		continue
	fi
	rm -f "$file"
	(
		APPDATA="$prof" LOCALAPPDATA="$prof" XDG_DATA_HOME="$prof" XDG_CACHE_HOME="$prof" \
			"$godot" --headless --path godot --script res://tools/balance.gd -- $t \
			> "$prof/log.txt" 2>&1
		echo "done $n: $t"
	) &
	running=$((running + 1))
	if [ "$running" -ge "$jobs" ]; then
		wait -n
		running=$((running - 1))
	fi
done
wait
"$godot" --headless --path godot --script res://tools/balance.gd -- report in="$out" md="$out/report.md" \
	> /dev/null 2>&1
echo "report: $out/report.md"

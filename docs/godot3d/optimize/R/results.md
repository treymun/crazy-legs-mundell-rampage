# Track R: the optimisation pass before v3.3.0 (2026-11-16)

Measured on the desktop (RTX 5070 Ti laptop, Windows, 1280x800 window) while
other helpers' Godot and Blender runs shared it, so every number is
**before and after back to back** (`88b05d3` copied to a scratch project
against this branch, runs alternated) and a median of runs. Absolute numbers
from different days do not compare.

## Window: `--view-bench=300` (3 runs each, ms a frame)

| Chapter | HIGH before | HIGH after | MEDIUM before | MEDIUM after | LOW before | LOW after |
| --- | --- | --- | --- | --- | --- | --- |
| hickston | 9.22 | 8.10 | 9.15 | 8.13 | 8.37 | 7.19 |
| fair | 5.93 | 5.61 | 7.21 | 6.21 | 5.50 | 4.94 |
| sawmill | 5.43 | 5.10 | 6.01 | 4.56 | 4.56 | 4.06 |
| quarry | 5.94 | 5.95 | 6.09 | 5.36 | 4.93 | 5.12 |
| bayou | 8.49 | 7.96 | 8.54 | 7.27 | 7.08 | 6.57 |
| speedway | 6.48 | 7.44 | 6.38 | 5.27 | 5.18 | 4.76 |
| mothership | 7.96 | 7.07 | 7.94 | 7.01 | 6.43 | 5.97 |
| **all** | **7.20** | **6.93** | **7.17** | **6.26** | **6.03** | **5.44** |

(One HIGH run of the new build caught an 11 ms stretch from the PC; the
speedway HIGH row is that noise. The frame's own work fell in every
chapter but quarry.) The view's parts, hickston fight, HIGH: actors 1.29 to
0.74 ms, props .33 to .30, setup .42 to .39, uniforms .30 to .28, the wait
for the frame 2.34 to 2.01; mothership: actors 1.14 to .91, uniforms .45 to
.30.

## The worst moments: `tools/stress_bench.gd` (HIGH, 2 runs each, ms)

| Scene | frame median | p99 | tick | render | instance slots |
| --- | --- | --- | --- | --- | --- |
| idle | 3.34 / 3.08 | 9.88 / 8.93 | .69 / .62 | 1.98 / 1.83 | 68 / 68 |
| strike | 5.75 / 6.10 | 12.8 / 13.8 | 1.81 / 1.86 | 2.67 / 2.71 | 80 / 80 |
| wreck48 | 8.38 / 8.24 | 22.9 / 21.6 | 3.31 / 3.16 | 4.53 / 4.40 | 620 / 620 |
| fire | 5.01 / 5.06 | 15.1 / 13.1 | 1.73 / 1.74 | 2.55 / 2.58 | 380 / 76 |
| arena | 5.62 / 5.15 | 14.9 / 11.8 | 1.03 / 1.01 | 3.41 / 3.12 | 772 / 468 |
| fivev5 | 6.77 / 5.76 | 14.8 / 13.9 | 3.66 / 3.39 | 1.86 / 1.50 | 448 / 164 |
| county | 13.3 / 13.0 | 26.8 / 25.8 | 2.84 / 2.85 | 7.41 / 7.04 | 760 / 504 |

(before / after). LOW (one run each): county 11.35 to 10.23 ms (p99 32.1 to
23.5), wreck48 5.28 to 5.24 (p99 10.3 to 8.9), arena 4.51 to 4.73.
Memory in the county scene: static 453 MB, textures 150 MB, buffers 54 to
69 MB, video 205 to 212 MB (the hidden actor models kept for reuse);
the idle scene 305 MB static, 97 MB video.

## Loading: `tools/load_bench.gd` (headless, median of 3, ms)

| Level | cold before | cold after | warm before | warm after | level mesh | wreck cuts |
| --- | --- | --- | --- | --- | --- | --- |
| hickston | 537 | 438 | 445 | 150 | 60 | 80 to 92 |
| fair | 525 | 442 | 417 | 119 | 50 | 103 to 125 |
| mothership | 644 | 572 | 367 | 110 | 46 | 253 to 282 |
| county_bayou | 576 | 551 | 475 | 142 | 63 | 109 |
| 15 levels | 5786 | 5124 | 4643 | 1535 | 634 to 651 | 1252 to 1363 |

Warm: the nav graph kept per level (0.25 to 0.3 s of every load); cold: the
nav graph's diagonal pass reads its lists in place. A wall broken through
now rebuilds its chunks: 3.4 ms against 59 for the whole level mesh.

## The tick: `tools/tick_profile.gd` (headless)

All chapters idle and fighting: 0.78 ms before, 0.77 after (wreck pieces'
contacts kept: hickston's fight wreckage 0.352 to 0.339 ms). The core (the
bodies, 100 hands, shots) is 0.45 ms of it, the 40 features 0.3; no single
listener idle over 0.05 ms. Enemies' own ticks are play and were left as
they are.

## Exports (2026-11-16)

Windows EXE 302.6 MB (engine 109 MB); Web pack 119.9 MB + 38.8 MB wasm (Lite
39.5 MB wasm); the APK was not built. In the pack: art.bin 49 MB (already
deflated per picture), sfx.bin 13 MB (16-bit PCM), the model scenes 39.5 MB,
music packs 63 MB (not in the web pack). Nothing was trimmed.

## Not measured

A phone, the browser's frame times, the APK, start-up to the title (only
the assets' 50 to 60 ms headless), the GPU's own time inside the
SubViewport (`--view-bench`'s card figure covers the root viewport only).

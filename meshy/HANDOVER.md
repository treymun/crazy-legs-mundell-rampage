# Meshy models track: handover (2026-11-26, fourth session)

Read `meshy/README.md` (method) and `SP/meshy-previews/INDEX.md` (every
version, every decision) first. SP = the session scratchpad.

## Fourth session (read first)

Done: 18c/17c quick fixes (steeper carry "carry_dir"/"carry_at": revenue
man's both hands on the gun; spectacle rim painted over "rim_px"; sheriff
"clearance" .05), 19b/19c jerry, 20 rudy. Credits now 907 of 2,500
(balance 2,031; jerry took three concepts). Paid calls one at a time.

New this session (all in meshy/tools):
- build_actor: "football" (a held part rebuilt as a pigskin), "to_body"
  [{x,y,z,near}] (vertices in a box ride the trunk: a sack, a back frame),
  "skin_rgb" (a gloved character's skin colour; Meshy's white gloves made
  rudy's face grey), "carry_dir"/"carry_at", "clearance" per kind.
- shed.py box rules: "cut" (the faces themselves go with the piece: a face
  mask, horns, a brim - a copy would leave them on), "radial" [x,y,z] (lift
  copies away from that point; Meshy normals point in here and there),
  "within"/"outside" (xy distance from radial), "head_only", "under": "cap"
  (paint the left-over in the cap colour), "shag" {shrink, amp, clamp} (the
  head under a helmet drawn in to a shaggy outline), "grow_dark", "rim_px".
  Hat rule: "within", "head_only", "radial"+"lift" (push the cut piece out,
  horizontal), "rim_drop", "cap_shift", "cap_ymin", "cap_shag",
  "cap_noise". Several rules may share one piece ("gear": name). Hat cuts
  now also bring long sliver tips down under the cut and split faces that
  touch a piece only at a corner (they stretched to the piece's bone when
  it flew off). 17/18/19 were built before those two fixes (rebuild before
  merging if their bare heads show a spike).
- Engine: ActorView._keep_arm_lengths - a blend no longer shrinks a forearm
  on a big swing (jerry's throw arm went to a tenth of its length).
- Look at a bare head: `meshy-work/headshots.sh <kind> <hide,bones> <cz>
  <out.png>` (worn above, bare below, four sides; KV_SCALE env).
  Scratch probes in meshy-work/scripts4: headcols.py (head faces by colour
  per height), piececheck.py (piece extents), above.py (vertices above a z
  by group: finds what a hat cut left), shard.py.
- bosses.cfg [boss_gear] "at"/"half"/"wide" are the old models'; when the
  models merge, rerun tools/gear_fit.gd and retune (jerry helmet now at
  [0.01, 0, 0.85] half .110).

Left, in order: foreman, baron, maw (+maw_bare), swamp_king; then the
humanoids (list below). Same recipe as jerry/rudy: prompts entry via a
small add_prompt_<kind>.py, meshy_kind.sh concept (look; retry if not
A-pose or props misplaced), model, kind_config, list old held parts from
dump/<kind>_poses.json (gear_skip strays, grip_parts when gold/white parts
pass for the old hands), iter.sh, headshots for the shed pieces, finish.sh
(SKIP_BUILD=1), boss checks.

## State

Branch `meshy-models` (all work committed; only `meshy_test/` untracked,
not ours). Credits: 801 of 2,500 spent (balance 2,137); third session: boss
(sheriff) 44, revenue_man 44 (run paid calls one at a time; ledger exact).
Third session done: 13c hog fix, 17/17b boss (sheriff), 18/18b revenue_man. The four concepts ran in parallel and
meshy.py's ledger kept one line for the 36; it was split by hand - run paid
calls ONE AT A TIME (meshy.py's ledger write is not safe in parallel).

Done and in INDEX: 06b big_billy, 07b drunk_coot, 08b/08c bottle_tosser,
09b barker, 10b/10c chum_tosser, 11b/11c noodler, 02d coot, 03g
yard_deputy, 05b alien; animals 12b/12c cow (physics video
12b_cow_death_physics.mp4), 14/14b gator, 15 crawler, 16 hound BLUE.
13b hog is NOT DONE (open): see below.

The branch's own checks: actor_check and live_body_check pass again
(fixed this session: `_keep_in_hand` interpolates the held thing's place
in the hand, so a blend's first draw no longer jumps; live_body_check
measures the clutch bare-handed - the coot holds pistol AND jug and a
holding hand never clutches - plus two new checks for that rule).
check_all quick: see the last line of this file for the latest result.

## Open, in order

1. ~~13b hog~~ DONE (13c): physics_beasts shot every beast inside a wall
   (Hickston's row 30 was walled in by pass 15); deaths now on open ground
   (OPEN 30.5, 26.5), and BeastDoll FOOT_SLIDE slides a dead standing
   beast's feet out (a crawler stood dead on its splayed feet). PHYSICS OK.
2. **Bosses** - boss (sheriff) 17b and revenue_man 18b DONE on the people's
   path (see "Bosses on the people's path" below; 18b's open items are in
   INDEX). Left: jerry, rudy, foreman, baron, maw, maw_bare (humanoid: same
   path), swamp_king (on his airboat: beast path or keep the boat). Hands:
   use "hands_paint": "texture" for every new kind (the flat master skin
   reads as paper hands up close: coordinator's note on 18) and leave
   skin_even off unless Meshy's arm paint is blotchy. Old notes: (baron, boss, foreman, jerry, maw, maw_bare, revenue_man,
   rudy, swamp_king; skip derby_champ) with their OLD weapon parts kept,
   and one boss physics video. Not written: build_beast.py needs the gear
   path (cut the old gear parts off the old mesh like build_actor's gear,
   keep them rigid on their bones, bake by emission and paste with a gear
   mask - gear_paste.py). Bosses are "scripted falls" in physics_check
   (no ragdoll) except where fit.json says otherwise; check
   physics_beasts' boss hand-over tests. Write concept requests like
   `SP/meshy-work/scripts2/beast_requests.py` (people-shaped bosses may
   suit build_actor.py instead - decide per boss: a humanoid boss with the
   people's rig gets hands, grips and the live body).
3. **Remaining humanoids** (build_actor path, unchanged): boilerback,
   chain_hand, chalk_spitter, flagman, gas_man, millhand, mundell,
   nitro_huffer, pit_mechanic, revenooer, shield_deputy, still_buster,
   tin_guard, tire_roller, valve_rat, drone (check what it is); skip
   lantern, probe, saucer, derby_champ; skeeter last.
4. Small open bits: noodler's red forearm cross-hatch and flat-peach
   hands; gator's dark crease at the back of the skull when the jaw lifts
   high; BLUE's lifted front paw folds flat at the wrist up close.

## Bosses on the people's path (third session)

build_actor.py with kind options (meshy/kinds/boss.json is the example):
- "phases": true -> textures ["", "p2", "p3"] (sooted / charred + blood from
  his own look); the held gear takes the old phase looks' gear texels
  (<kind>_gear_p2/p3.png, gear_paste.py).
- "shed": {name: rule} (meshy/tools/shed.py): boss_gear pieces as their own
  bones "<name>_gear" (actors.json "gear" written from them; labels/segs of
  the bone they ride). Hat rule {z, keep_z, keep_x (antennae kept on the
  head), cap (skull cap height share), cap_colour, stalk_colour, ring_pct,
  cap_base, cap_grow}; box rule {box{x,y,z}, hue, sat, val, lift} copies the
  faces out (a badge). Find the z's with scratch scripts3/headprobe.py and
  goldprobe.py on the built glb (rest pose), then look at the bare head with
  `KV_HIDE=hat_gear,badge_gear KV_SCALE=.7 KV_C=0,1.95 blender -b -P
  meshy-work/keys_zoom.py -- glb png out keys angles`.
- "akimbo": [side] a fist on the hip (elbow out) in every living key.
- "grip_parts": {side: [old bones]} when the colour rule takes gold/white
  parts (badge, hat, white gloves) for the old hands; "gear_extra" for gold
  gun parts the skin rule would drop; "gear_skip" stray bits.
- For a masked/gloved boss: "skin_zones": ["hand_l", "hand_r"],
  "face_lift_most": 1.0 (else the face lift and skin passes paint the
  sleeves orange and lighten the mask); "gloves" [r,g,b] not too light
  (it clips white); pale cloth needs more colour or it dithers pink
  ("recolour" hat_straw in boss.json).
- tour_for.py adds a "p2" shot for bosses (ingame_sheet day_p2/night_p2).
- Physics video for a boss: boss_end_frames.gd big=<every 2nd frame> then
  ffmpeg (17_boss_fall_physics.mp4; the commands are in this session's
  INDEX line 17).
- Bosses have no hit-reaction rows in live_frames (all rows read the same).

## The beast path now (build_beast.py; meshy/tools/beast.sh <kind> <NN>)

`beast.sh` builds, installs, renders the beast make sheet
(`beast_sheet.py`: four sides at the standing key, every key side-on and
three-quarter, old above new, turned by fit.json's "front") and reverts
import churn. Then: `ingame.sh <kind> <cells>` + `ingame_sheet.py` (animals
by day on Hickston's open street; hog and hound are not play's hands, so
the tour cannot stand them up: use the death rows for the hog and
`tools/hound_frames.gd` for BLUE), `SP/meshy-work/deathcmp.sh <kind> <NN>
<rows>` (old/new death rows stacked), `ROW_VIDEO=1 death_frames.gd ...
audit rows=...` (every other tick as video_<row>_NNN.png; move into
<dir>/<row>/ and run make_video.py), physics_check (BEASTS rows).
Kind config (meshy/kinds/<kind>.json), on top of the old ones:
- "weights": "heat" - Blender bone heat over stand-in bones along each old
  part (the default "nearest" old face fails wherever Meshy's shape
  reaches past the old blocks: tails, barrels).
- "groups" [[bones]] - weighted as one (first = takes the weights); from
  the old BeastRig segments (`SP/meshy-work/gds/beast_segs.gd` ->
  beast_segs.json). Parts the LIVE keys move apart are split off again
  (jaws, tail pieces) unless "split": false.
- "legs" [[root..foot]] + "torso": realign_legs moves each old leg (bones
  and keys) to the Meshy leg; written to actors.json "beast_legs" and
  BeastRig uses those bones instead of searching for blocks. "realign":
  false (leave), or "mesh" (move the Meshy legs onto the old ones - for a
  kind whose gait speeds are tuned to the old feet, BLUE). "square"
  (default true) sets the feet square in pairs from the hock down.
  Leg heat weights are capped at the old legs' tops ("leg_band").
- "jaw" {upper, lower, mouth, throat, throat_low, pitch}: the closed Meshy
  mouth cut along the lips, the lower jaw rigid on its bone, the inside a
  painted bag (teeth, palate, tongue, throat).
- "tint" [r,g,b], "gain", "greys" {rgb, sat}: colour; undersides always
  take the Meshy albedo at the sides' light ("belly_light").
Engine/tool changes this session: BeastRig named legs, skinless bones not
taken for a knee, FOOT_OUT .2; physics_ragdolls reads skinned vertices'
strongest bone and skips unskinned held meshes, lying-height bound by the
torso's width for beasts; physics_beasts names the stretched link and
allows 3.5 cm more in a hit; death_rows ROW_VIDEO; tour_for animals.

## The previous session's pipeline additions

- `held_model` {glb, length (m at 1.73 height), tris, tails [shares of its
  length], band, grip (share from the front), plumb, follow}: a held thing
  made with Meshy (the noodler's catfish, `meshy/assets/catfish.glb`). It
  replaces the old gear's geometry at the old place, is baked LIT with the
  body (material slot 3, gear-mask value 0.1: not pasted, kept free of
  blood), held in "bottle" mode by its snout but hung plumb from the grip
  (`plumb()` re-hangs it in carry/walk keys and after every keep-out step;
  wind/fire swing it back/forward for the slap).
- Held things can carry their own bones: the fish is cut into rigid pieces
  at each tail joint, each its own unskinned mesh on bone
  `<gear>_t1`, `_t2` (rest on the joint, keyed rigid with the thing);
  actors.json `flop` {tail: parent}; tails are in `rides` too.
  Engine: `src/view3d/held_tail.gd` (HeldTail: damped spring per tail bone
  on the joint's smoothed acceleration and gravity, plus a periodic
  wriggle; looks only), stepped by ActorView after the pose each frame
  while alive; RagdollRig `_take_flop`/`_root_of` cluster tail bones with
  their root so the dead body drops the whole fish as one piece.
- `throw_body` {key: [twist back deg, lean fwd deg, weight fwd m, to front
  foot m, hips lowered m]} (defaults for wind/aim/fire/recover): the
  thrower's trunk coils and drives; `recover` gets a follow-through arm;
  `throw_out` (cocked hand out from the head).
- `meshy/tools/build_beast.py`: the beast path (above).
- Scratch helpers in `SP/meshy-work/`: `iter.sh <kind> <NN> [keys]`
  (build+install+make+hands sheets, no in-game runs), `keys_views.py` +
  `strip.py` (any keys from any sides: used for 08c_..._throw.png),
  `zoom_video.py` (close-up clip of live_frames video rows: the 11c flop
  video).

## Checks

Fixed this session: actor_check (blend jump) and live_body_check (clutch)
pass. physics_check fails only on the hog blast (open item 1). hound_check,
hound_walk_check and hound_pace check pass with the new BLUE. Lint and
gdformat clean on src/tools/addons (run from godot/ so its config applies).
Scratch diagnostics in SP/meshy-work: gds/beast_pts.gd (rig balls),
gds/beast_legs.gd, gds/beast_segs.gd, scripts2/label_render.py (the built
mesh coloured by strongest bone at a key: the way to see bad weights),
scripts2/jaw_find.py, scripts2/torso_turn.py, deathcmp.sh, unchurn.sh.

## Kind-config options for people (build_actor.py)

- `skin_even`: true or {ext, arms, light, floor, smooth, face_even, tone}:
  bare arms/hands/face to the old cel's skin tone, blotches gone. Use
  `{"ext": false}` when pale boots/aprons could be taken for skin, and
  `{"ext": false, "arms": false}` for sleeves to the wrist.
- `belly`: {z, k, rx, ry, rz, depth, front} swell the trunk's front.
- `nose`: {k, r, z:[lo,hi] (share of height), reach} bulb nose; find the
  face's z band first (scratch script `meshy-work/scripts2/heads.py`).
- `recolour`: list of {name, z, x, y, hue (wraps), sat, val, to, contrast,
  not_skin, at:"nose", r}. Hats/caps above the skin need `not_skin: false`.
- `hold_near` (gun hand distance share, e.g. 1.08 for a big belly) and
  `hold_legs` (carried things kept off hips/knees) - read by RagdollRig and
  LiveBody (engine change on this branch).
- `item_types` per side: pistol, throw, raise (megaphone), bottle (neck
  across the palm), hold (old grip and orientation), carry (default).
- `carry_top`: "hand" (default) or "up" (hang from the highest point).
- `megaphone`, `bandolier` {from, count, span, height, radius, colour,
  tilt}, `gear_one`, `gear_skip`, `gear_drop` [{part, above}],
  `gear_snap`, `grip_skip` [side], `gloves` [r,g,b], `relaxed_curl`.

## Shared fixes for people (every rebuild gets them)

Hands unwrapped on their own + tiny hand UV islands moved onto the skin
(dark finger-root slivers gone); forearm cut rim evened (wrist panels and
spikes); pistol muzzle from the old aim key (was backwards); relaxed free
hands; `hand_flips()` only reports folded hand faces (weight relaxing made
it worse, left off).

## Gotchas

- Blender resolves a RELATIVE image save/load path somewhere else (not the
  cwd): use `os.path.abspath` for every path a script writes (a missing
  baked png makes build_actor_meshes.gd sit forever).
- Never kill Godot by name (the owner's game may be running): find yours
  by command line (`--path godot` from the worktree).

- Godot strict typing: `info.get()` is Variant; assign to a typed var
  (`var x: float = info.get(...)`) - casts and constructors fail the build
  and a headless tool then waits on the debugger forever. `meshy-work/gd.sh`
  now feeds `< /dev/null` so it exits instead.
- After every install, revert `.glb.import` churn before committing.
- The make sheet's default keys skip `wind`; pass keys
  (`make_sheet.sh <kind> <out> <title> w1,wind,aim,fire,pain,die_2,down`).

Last check_all quick (third session, after 18b/17b, scratch profile): ALL
CHECKS OK (54 checks listed ok, 154 s). physics_check, actor_check,
boss_check, boss_end_check, boss_rematch_check, arena_wreck_check,
live_body_check, view3d_check also run alone: OK.
Scratch for this session: SP/meshy-work/scripts3 (headprobe, goldprobe,
backprobe, partcol, partbox, islands, meshy_view), gds/hog_blast.gd and
crawl_diag.gd (ragdoll stretch diagnostics), keys_zoom.py (KV_SCALE, KV_C,
KV_HIDE). The hands sheet script is meshy-work/scripts/hands_render.py
(iter.sh points at a wrong path for it).

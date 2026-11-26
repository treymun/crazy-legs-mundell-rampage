# Meshy models track: handover (2026-11-26)

Read `meshy/README.md` (method) and `SP/meshy-previews/INDEX.md` (every
version, every decision) first. SP = the session scratchpad.

## State

Branch `meshy-models`, last commit 662843f2 plus this handover (all work
committed; only `meshy_test/` untracked, not ours). Credits: 557 of 2,500
spent (balance 2,381): catfish 39, cow 39 this session.

Done and in INDEX: 06b big_billy, 07b drunk_coot, 08b/08c bottle_tosser,
09b barker, 10b/10c chum_tosser, 11b/11c noodler, 02d coot, 03g
yard_deputy, 05b alien. 12 cow is in INDEX as NOT DONE (open).

## Open, in order

1. **12 cow (beast path, WIP)**: `meshy/tools/build_beast.py` with
   `meshy/kinds/cow.json` works end to end (build, `install.sh`, make
   sheet). To do: (a) the dead key ("down", legs up) stretches and twists
   the legs where weights are softened over the hips - try `"smooth": 1`,
   or soften only along a leg (not across body/leg), or keep the hip ring
   rigid; (b) the in-game sheet, probes and death rows (`finish.sh` is
   people-shaped: `live_frames` rows and the hands sheet assume a person;
   check what `ingame.sh` and `death_frames.gd` do with a beast) and the
   PHYSICS VIDEO for one animal (the cow's death ragdoll, BeastDoll); (c)
   a beast make sheet framing (render_make crops by the people's height);
   (d) a hurt look (`build_beast.py` writes the plain look for kinds whose
   old entry has "hurt"; cow has none).
2. Then hog, gator, hound (BLUE - the dog; careful, a big feature),
   crawler with the same path (concept from the old three-quarter render +
   cel by image-to-image, 9; image-to-3d, 30; no rig). Write request bodies
   like `meshy/requests/cow_concept.json` (make_requests.py is
   people-shaped). Each old armature here is flat (no parents), rigid parts
   (one bone a vertex), rest = standing key: the "carried back to rest"
   step is there for any that differ.
3. Bosses (baron, boss, foreman, jerry, maw, maw_bare, revenue_man, rudy,
   swamp_king; skip derby_champ): the beast path plus their gear - the old
   weapon parts must be kept as they were (cut off the old mesh like
   build_actor's gear, baked by emission and pasted with a gear mask). Not
   written yet (`build_beast.py` docstring says so). Physics video for one.
4. Remaining humanoids: boilerback, chain_hand, chalk_spitter, flagman,
   gas_man, millhand, mundell, nitro_huffer, pit_mechanic, revenooer,
   shield_deputy, still_buster, tin_guard, tire_roller, valve_rat, drone
   (check what it is); skip lantern, probe, saucer, derby_champ; skeeter
   last. Look for gloved characters (`gloves`), hats/noses/cap colours that
   Meshy got wrong (`recolour`, `nose`). Overhand throwers now get the
   whole-body throw (`throw_body`) automatically; carriers want
   `hold_legs`.
5. Small open bits from INDEX: noodler's red forearm cross-hatch (Meshy
   paint) and flat-peach hands; `skin_even` on noodler turned forearms a
   grey-tan that did not match his pink upper arms (reverted - its arm zone
   stops at the elbow).

## This session's pipeline additions

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

## Checks this session

check_all quick: actor_check ("blend: the first draw of a new pose jumped",
billy) and live_body_check ("a hand goes to the chest wound", inf) FAIL on
this branch already at 682f929f without this session's engine changes
(checked by stashing them); tune_check and physics_check failed once in
the parallel run and pass alone. Nobody has run the full lint suite since.

## New kind-config options (build_actor.py) this session

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

## Shared fixes this session (every rebuild gets them)

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

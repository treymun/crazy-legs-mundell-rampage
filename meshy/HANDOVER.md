# Meshy models track: handover (2026-11-26)

Read `meshy/README.md` (method) and `SP/meshy-previews/INDEX.md` (every
version, every decision) first. SP = the session scratchpad.

## State

Branch `meshy-models`, last commit bad18412 (all work committed; only
`meshy_test/` untracked, not ours). Credits: 479 of 2,500 spent (balance
2,459), no paid calls this session.

Done and in INDEX (sent to the owner by the main session): 06b big_billy,
07b drunk_coot, 08b bottle_tosser, 09b barker, 10b/10c chum_tosser, 11b
noodler, 02d coot, 03g yard_deputy, 05b alien.

## Open, in order

1. **11c noodler catfish (owner asked)**: the old fish mesh reads as a flat
   dark wedge. Make a new catfish with Meshy (~30-40 credits; text/image to
   3D of a big channel catfish held by the jaw: wide flat head, barbels,
   small eyes, mottled grey-olive back, pale belly, forked tail), decimate to
   a game budget, put it in as the held thing (replace the gear source like
   the `megaphone` option does: see `MEGA`/`megaphone` in build_actor.py),
   rigid in his right fist by the lower jaw, body hanging. Tail flop: give
   it one or two tail bones skinned in the held mesh (held things are
   unskinned today: needs a small extension - a held mesh with its own
   bones under the gear bone, swung by a spring in actor_view; looks only).
   Keep the ledger (balance before/after).
2. **08c bottle_tosser (coordinator, not blocking)**: whole-body throw -
   torso twist back on the wind-up, drive forward on release, weight onto
   the front foot, plus a short follow-through (use the `recover` key).
   Throw code: the `"throw"` branch in `solve()` (search `mode == "throw"`);
   torso is `D["body"]` built earlier in solve (see how the shouldered aim
   blades the body with `aim_twist`).
3. Bosses and animals (cow, hog, gator, hound BLUE, crawler, bosses): keep
   each old armature and its animations, skin the Meshy mesh onto it by
   weight transfer from the old mesh (Blender Data Transfer, nearest face
   interpolated). One animal and one boss get a physics video
   (`tools/make_video.py`).
4. Remaining humanoids: boilerback, chain_hand, chalk_spitter, flagman,
   gas_man, millhand, mundell, nitro_huffer, pit_mechanic, revenooer,
   shield_deputy, still_buster, tin_guard, tire_roller, valve_rat, drone
   (check what it is); skip lantern, probe, saucer, derby_champ; skeeter
   last. Look for gloved characters (use `gloves`), hats/noses/cap colours
   that Meshy got wrong (use `recolour`, `nose`).

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

- Godot strict typing: `info.get()` is Variant; assign to a typed var
  (`var x: float = info.get(...)`) - casts and constructors fail the build
  and a headless tool then waits on the debugger forever. `meshy-work/gd.sh`
  now feeds `< /dev/null` so it exits instead.
- After every install, revert `.glb.import` churn before committing.
- The make sheet's default keys skip `wind`; pass keys
  (`make_sheet.sh <kind> <out> <title> w1,wind,aim,fire,pain,die_2,down`).

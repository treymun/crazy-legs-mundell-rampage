# Meshy models track: handover (2026-11-26, seventh session)

Read `meshy/README.md` (method) and `SP/meshy-previews/INDEX.md` (every
version, every decision) first. SP = the session scratchpad.

## Agent B (branch meshy-models-b, worktree SP/p18-meshy, work SP/meshy-work-b)

List, in order: millhand, mundell, nitro_huffer, pit_mechanic, revenooer,
shield_deputy, still_buster, tin_guard, tire_roller, valve_rat, drone (alien
grey, see 05b), skeeter. Budget 650 credits (ledger section "agent B",
running total in its "spent").
DONE (all with INDEX lines): 40 millhand (44 cr), 41 mundell (44 cr), 42 nitro_huffer (53 cr: two
concepts, the first used; dynamite = gear_extra b33,b35..b50, gear_skip b31,
gear_one, item_types r throw, "bottle_flip" (new) + bottle_grip .72 so the
spark stands up out of the fist; skin_even tone with face_even 0 (else the
sandy hair went skin-peach); face_keep light .78 (the evened arms raised
the face's target)).
43 pit_mechanic (44 cr; lug wrench: grip_parts r b27 l b31, gear_one,
item_types r "hold" (throw/bottle mode could not take a cross: wrist 63
degrees, 3 cm in the body); cap recolour with "not_face" (new: the cap's
band reached the brow) split into crown z .93+ and a band z .90-.93 by
saturation so the dark hair stays).
44 revenooer (44 cr; revolver item_types r pistol, grip_parts r b42 l b45;
the Meshy pale skin went grey-yellow: face_keep "gain" .78 (absolute, new),
"tone" [186,124,98] "tone_k" .75 "tone_zone" "head" (new: the face, neck
and ears toned warm at their own light; dark hair/hat left out by a light
floor, r-b and saturation tests), hands skin_even tone [176,116,92] light
.88 face_even 0 + hand_smooth 2; recolour fedora z .94+ charcoal, back hair
x +-.065 y > .03 dark (the tone speckled them orange)).
44b revenooer (0 cr; hair recolour boxes: hair_top z .917-.94 not_face,
hair_back z .885-.917 y>.05, hair_nape |x|<.065 y>.03; fedora_back; collar).
45 shield_deputy (44 cr; revolver r pistol, the riot-door shield l "hold"
with "follow_old" [gear1] (new: the shield keeps the old one's own motion,
the hand put on it as at the standing key - riding the new forearm's turn
swung it out flat) and "hold_out" {gear1: .12} (new: the shield 12 cm
ahead of the hand, the fist behind it, not through its window);
grip_parts r b57 l b61 + gear_skip the same (the old hands shrink with the
gear); gear_extra b25 (gold star); skin_zones head+hands (sleeves); hat
and shirt recolours. Open: the back of the hat brim stays tan (recolour
boxes by z/y did not reach it - its texels may share UV space; not solved).
45b shield_deputy (0 cr; recolour "smooth" (new): shirt/sleeves/collar
khaki [150,126,88] smooth 8, sat<.55 keeps patches/star; hat smooth 6).
46 still_buster (44 cr; fire axe one-handed: item_holds {"0": {"r": .78}},
item_types r "hold", follow_old [gear0] + "follow_wrist" 65 (new: the
wrist bends at most 65 degrees off the forearm, the axe turning with the
hand the rest; the followed item's elbow now points along the hand);
grip_parts r b39 l b42, gear_extra b33-36 (red axe head), gear_skip b18;
hands skin_even tone [176,112,88]). Open: the fire key holds the axe
across the chest (the old fire chopped down-forward; the wrist clamp turns
it) - a "fire" chop pose would need its own authored key; the axe body
and the hands are the old cartoon ones.
Two-handed tries for the axe (two_old + two_both + "two_old_shift" (new,
kept in the tool)) left the left hand 15-40 cm short of the haft: the old
model held it one-handed.
47 tin_guard (44 cr; alien grey in riveted tin armour, open-face helmet;
the old coil gun r "pistol" one-handed + the old red shield l "hold"
follow_old [gear1] hold_out .12; grip_parts r b62 (old right hand), l b85
(shield boss: the old dump's LEFT ARM tracks the shield, the real old left
arm b63/b64/b66 is labelled body); gear_extra b56 b82 (orange muzzle cap
and the shield board passed for skin); gear_groups (new) gun b7-b57 /
shield b82-b87; item_holds {"0": {"r": .59}, "1": {"l": .81}};
pistol_low (new) r [20, 25, .35] + pistol_aim_drop .12, pistol_aim_in
-.05, pistol_wind_out .8 (a 0.76 m gun with a stock behind the grip:
along a raised forearm it stood past the face, at the eye line its rear
went into the face); follow_wrist 60 + follow_wrist_keep (new). Colour:
skin_zones hands only (the face pass took the helmet for skin), recolour
armour/suit by val with not_skin false + not_hands (new), then face boxes
by hue (the suit is tagged by a blue-ish [48,47,50] so the eyes rule can
find the eye texels after it) - neutral greys dither beige/blue in the
grade: use the old warm greys. Known: jaw edge of the green face is a
little jagged; gear probe 5 cm legs row picture 11 (wind blend).
47b tin_guard (10 cr: a Meshy RETEXTURE, v1/retexture on the model task,
enable_original_uv, "clean riveted gun-metal plate" prompt; coordinator
held 47: granite armour, sticker face, pale shield hand). The retexture
made clean plates but a grey robot mask face, so the texture is
composited: meshy/tools/retex_swap.py (Blender: "polys" = UV polygons of
the faces whose centre is in build-space boxes; "swap" = the rigged glb
with its image replaced) + retex_comp.py (the original texture inside the
polygons, the retexture elsewhere) -> meshy-work-b/meshy_out/
tin_guard_rig_rt/rigged.glb (kind "rigged"). Then: texture 1024 (at 512
the plate read as granite blocks), recolour "steel" with "keep_light"
(new: each texel keeps its own light, only the hue set - the warm dusk
bake stepped grey steel into beige/blue palette specks; neutral greys
have a clean ramp in the VGA palette) and "not_boxes" (new: the face
boxes left out), a visor band, brow specks, eye glints (tiny boxes);
face_keep gain .95 + tone; gloves [62,62,64] glove_shade (gauntlets).
The 47 config is kept as meshy-work-b/tin_guard_47.json.
48 tire_roller (44 cr; the old tire, two_old + two_both, aim_keys [],
gear_one, two_old_in 0 + two_old_shift [.05, 0, .06] (centred on the new
deep belly), item_axis (new) {"0": [1,0,0]} (a disc's long axis is any way
in its plane: across the body) + item_holds r .03 / l .97 (the hands on
the rim's sides - at .15/.85 the palm went to the bottom of that slice),
grip_parts r b139 l b142 (old hands hidden behind the tire), gear_skip =
the arm-labelled gear parts (old fingers on the rim, flesh blobs),
gear_extra = the rest of the dump's gear groups (orange ring pieces passed
for skin); hold_legs; skin_even tone + face_keep tone_zone head + scalp/
nape/by_ears/chest_skin recolours (the bald head came out grey-blotched),
undershirt smooth recolour boxed to the torso (|x| < .2: else the arms'
pale skin went cream). Known: the live probe shows the tire 8-10 cm in
the body in the pain reaction (key 9) though the old pain key hides it
(scale 0) - the live view seems to show it; not solved.
48b tire_roller (0 cr; coordinator: dark band across the crown, a tone
step down the nape, pale specks): ONE "head" recolour z .80-1.1 not_face
val .26+ contrast .35 smooth 6 (separate scalp/nape/ear rules each had
their own median: the steps), "face_hi" only_face val .72+ pulled to a
warm tan (Meshy's sweat highlights clipped to white specks), face_keep
eyes 0, chest_skin contrast .4 smooth 5.
49 valve_rat DONE (third B session; 88 cr in all: the first concept/
model/rig 44 kept in meshy-work-b/meshy_out/valve_rat_*_49 + config
meshy-work-b/valve_rat_49.json, then a NEW concept/model/rig 44: prompt
"STANDING TALL AND UPRIGHT", "short close-cropped hair", the brass twin-
tank pack described, plus "extra_refs" = the 49 concept (same face) and a
crop of the old model's side/back views (the tanks); prompts entry kept as
meshy-work-b/prompts/valve_rat_49.json). Build: "to_body" box x +-.3,
y .13-.42, z .44-1.16 near .05 (the tanks ride the trunk only: Meshy gave
their bottoms to the thighs); "hair_smooth" (NEW build_actor option, see
the tool list) on the back/side hair under the cap (spiky cards rounded)
+ a "hair_back" recolour (x +-.15, y 0-.115, z .80-.893: the tank tops sit
behind the head at the same height, keep y < .12); carry_both, carry_dir
[.9,.38,.15] carry_at [.10,.24,.06] (lower carries left the right hand
3-9 cm short of its grip on his short arms); upright_deg 2; NO head_keys
(any head lift smears the jaw: the chin lies in the neck blend); FACE:
skin_zones hands only + face_lift_most 1 + face_clean {detail .85, hue
.85, keep_white .85} and NO face_keep (face_keep's no-shadow bake misses
face islands and left salmon/grey shards; the skin passes lifted the
face x1.2). tris 18000 (the gap-tooth grin went jagged at 14000).
Known: the right fist sits under the pipe in the stand/walk (fingers
closed short of it; the grip window takes in the valve wheel), gear probe
9.6 cm in one running/pain blend picture, back/side arm views hidden by
the tanks (front views 63-100%); the graded face steps salmon/grey.
NEXT: valve_rat (finish, see 49), drone (alien grey, see 05b
alien.json), skeeter (dumps ok=false: a bug - beast path; see the
beast-path section and A's swamp_king notes), then as credits allow the
millhand Meshy chainsaw (<= 20 cr: held_model, orange/red body, grey bar
and chain) and a still_buster chop fix (axe down-forward in "fire").
Credits: agent B 459 of 650 after 49's rig.
check_all quick (second B session, after 47b/48b, old valve_rat in the
game, scratch profile): 1 FAILED in 171 s - hud_layout_check (a SCRIPT
ERROR in Enemy._init under check_all's parallel load); hud_layout_check
alone right after: HUD LAYOUT OK. Everything else ok. check_all quick batch 2 (44-46)
run after 46 (scratch profile): ALL CHECKS OK in 190 s; batch 1 (40-43) ALL
OK except net_errors_check under load,
OK alone.
Mundell notes: the player kind is no enemy - the enemy tour, live_frames
probe and death_frames cannot spawn it (SCRIPT ERROR / empty frames). His
in-game sheet is tools/mode_frames.gd only=mundell (new: gd.sh, old:
gd_old.sh) composed old|new; after a mundell model change also run
tools/art/build_player_down.gd then pack_assets (player_down_*.png).
Long gun: cheek_weld with "cheek_at" [.045,.07,.065] (a bearded jaw: the
default point sat on the beard), "aim_drops" down to -.12 (butt raised to
the cheek), "head_keys" aim/fire/wind [10, 35, 0] (the old head looked up
off the barrel after the weld), "tris" 13000 (a decimated cap triangle hung
green over the brow at 10000); face_keep "soften" .7 (lit wrinkle creases
baked as dark crack lines: lifted toward the neighbours' median).

Setup (all agent B's own; never A's places):
- `. SP/meshy-work-b/env.sh` sets MESHY_WT=SP/p18-meshy, MESHY_WORK=
  SP/meshy-work-b, MESHY_AGENT=B, MESHY_BUDGET=650 and a scratch APPDATA/
  LOCALAPPDATA under meshy-work-b/appdata. Then the usual tools work:
  `sh meshy/tools/meshy_kind.sh <k> concept|model`, `kind_config.py`
  (writes ../meshy-work-b/... paths), `sh meshy/tools/build.sh <k> <NN>`,
  `SKIP_BUILD=1 SKIP_INGAME=1 sh meshy/tools/finish.sh <k> <NN>` (probe and
  death rows), then in meshy-work-b `sh sheets.sh <k> <NN> <face cz>` and
  `sh checks.sh actor_check,live_body_check,physics_check`.
- meshy-work-b has its own gd.sh / gd_old.sh (gd_old runs the untouched
  tree SP/p16-meshy-old, own profile), iter.sh, headshots.sh, sheets.sh,
  checks.sh, aimview.sh, facetry.sh, unchurn.sh, keys_zoom/keys_views/strip;
  prompts in meshy-work-b/prompts/ (<kind>.json; add_prompt.py <kind>
  <json> puts it in prompts.json). Dumps of all 12 old kinds are in
  meshy-work-b/dump (skeeter dumps ok=false: a bug, beast path).
  meshy-work-b/old holds the old glbs/textures and the untouched tree's
  actors.json (build_actor reads it next to old_glb).
- A's 04g commit (face_clean / face_uv / cheek_weld) is cherry-picked here.

Tool changes by B (all opt-in; defaults unchanged for A):
- tools/*.sh: MESHY_WT / MESHY_WORK env (default p16-meshy / meshy-work);
  finish.sh SKIP_INGAME=1 (no in-game sheet: minor enemies).
- meshy.py: MESHY_AGENT/MESHY_BUDGET keep a ledger section "agent <X>"
  (entries, budget, running "spent"); if the shared balance moved by more
  than a call's price (the other agent's call landed meanwhile) the entry
  records the nominal price (9/30/5) and "balance_moved".
- kind_config.py / make_requests.py: MESHY_WORK env.
- build_actor.py "two_old": a two-handed tool (chainsaw) moves as the old
  one did in every key, brought in by the chest ("two_old_in" x the forward
  fix); use with "aim_keys": [] (nothing shouldered). "two_both": the other
  hand stays on it in every living key but pain.
- build_actor.py "face_keep": true or {light, blend, zone, eyes, eye_sat,
  eye_lum}: after every skin pass, the face's front (FACEZONE; widen it with
  "face_box" {"r": .27} for a big head - the Meshy Head bone sits at the
  back of the skull, so at r .17 the eyes fell outside it) is taken back
  from the head's no-shadow bake at the finished skin's light. "eyes": k
  sets the eye whites/teeth (pale grey in Meshy's albedo; the dusk bake
  makes them peach and the grade dithers them into the skin) to grey at k x
  the face skin's light; it triggers the albedo bake. millhand:
  {"light": 1.15, "eyes": 1.6}. Use it where face_clean smears the eyes or
  blotches a bearded face (face_lift reads a beard as dark skin and lifts
  it: "face_lift_most" 1.15 for a full beard).
- face_uv for a hard hat: "brim_k" 1.4 (.7 shrank the whole hat and the
  face's other islands: blockier), "z" [-.16, .2], "r" .2, k 3-4.5.
- build_actor "follow_wrist" deg, "two_old_shift" [x,y,z], recolour
  "smooth" passes; "MESHY wrists over 45" log line per key.
- build_actor "follow_old" [gear bones], "hold_out" {gear: m} (one-hand
  things: shields).
- face_keep "gain" (absolute light), "tone"/"tone_k"/"tone_floor"/
  "tone_zone" "head" (warm a grey Meshy skin), "soften", "unhue".
- build_actor recolour rule "not_face": true leaves FACEZONE out.
- build_actor "bottle_flip": a bottle/throw item whose thick end is its
  top (dynamite spark).
- build_actor (47): "gear_groups" [[old bones]] (each list one held thing,
  the lists alone decide); "pistol_low" {side: [barrel deg down, arm deg
  ahead, out share]} (carry/walk/pain keys of a long one-handed gun, the
  frame flattened; pain flings it up and out); "pistol_aim_drop",
  "pistol_aim_in", "pistol_wind_out"; "follow_wrist_keep"; recolour
  "only_face", "not_hands", "albedo_hue"/"albedo_sat" (Meshy unlit colour;
  triggers the albedo bake). MESHY_DEBUG_KEEP now also names the bone for
  the solve's own keep-out lines.
- 48: build_actor "item_axis" {gear index: [x,y,z]}.
- 49 (third session): build_actor "hair_smooth" [{x, y, z (m, build
  space), iters, k, fade}] - the Meshy hi mesh's vertices in each box
  Laplacian-smoothed (by place, so UV seams stay shut) before the bake:
  spiky hair cards draw in to a rounded mass. valve_rat: x +-.17, y -.03
  to .14, z .93-1.10, iters 10, k .6, fade .02.
- build_beast.py is A's version copied whole (A's 27/27b commits:
  keep_parts, meshy_uv, light hemi, smooth_normals...; all opt-in, the
  animals' defaults unchanged) - the same file on both branches now.
- 47b: recolour "keep_light" k, "not_boxes" [{x,y,z}]; meshy.py NOMINAL
  v1/retexture 10; meshy/tools/retex_swap.py + retex_comp.py (see 47b).
- grip_parts: the old millhand's yellow coat passed for skin (b5); name the
  old hands (b40/b41 right, b45 left) or the saw is held by one hand.

## Seventh session (read first, then the sixth)

SPLIT (coordinator, 2026-11-26): agent A (this branch, meshy-models) keeps
clone/jerry fixes, the long-gun pose sweep, baron 22c, swamp_king, and the
humanoids boilerback, chain_hand, chalk_spitter, flagman, gas_man. Agent B
(scratchpad/p18-meshy, branch meshy-models-b, own SP/meshy-work-b) takes
millhand, mundell, nitro_huffer, pit_mechanic, revenooer, shield_deputy,
still_buster, tin_guard, tire_roller, valve_rat, drone, skeeter. Leftovers
(rudy, maw dryer, alien hand holes, hat-cut rebuilds, gear_fit): whoever
finishes first, ask the coordinator. A's credit budget: stop at 2,007 total
in the ledger (650 on top of 1,357). INDEX.md is shared: append one line in
one write only. Minor enemies: no in-game sheet; per model actor_check,
live_body_check, physics_check (+ boss checks for bosses); broad checks and
check_all quick once per ~4 models.
B: PULL face_clean / face_uv / cheek_weld (build_actor.py + face_clean.py,
commit of 04g) for your long-gun and hatted characters.

New kind options this session (all opt-in, build_actor.py):
- "face_clean": true or {detail .55, hue .6, floor .62, eye_lift 1.15,
  hair_hue 31, blend 1} - the face's front (and neck, and the skin behind
  the ears) rebuilt from Meshy's albedo bake (meshy/tools/face_clean.py):
  the finished skin colour with the albedo's own variation a share, the
  light from the head's no-shadow bake (median-filtered), grime eased,
  eyes kept at full contrast. Fixes stubble/grime turning into lilac
  "rot" blotches and unreadable eyes. Zone: "face_box" {r .17, z [-.16,
  .16], back -.025, back_top .08} (m at 1.73, about the Meshy Head bone,
  which sits at the BACK of the skull at jaw height).
- "face_uv": {k 2.6, brim_k .7, r, z} - the face's UV islands take k times
  the texture scale, a hat brim brim_k (a straw brim had 12x the face's
  texels: eyes were 5 texels across at 512).
- "cheek_weld": true - shouldered long gun: the head is pitched/rolled
  until the gun-side cheek lies on the stock (cheek_at [.04,.065,.03]);
  the stance search then also tries raising the butt ("aim_drops", default
  [-.06,-.03,0,.02,.04] with the weld, else the old [0,.02,.04]) and
  scores the cheek gap. "aim_holds" {side: share}: grips on the
  shouldered gun (the old carry grips .4/.7 on the clone's 1.13 m gun put
  the arms out straight and the body leaning after them). "aim_skip"
  (.22), "upright_aim_deg" (14; clone 4), "aim_head_pitch" (only without
  the weld), "wind_clear" (low ready kept off the body; did not change the
  chest probe).
- Scratch: MESHY_DEBUG_KEEP=1 prints which body bone a keep-out hit;
  MESHY_DUMP_FACE=<npz> dumps the finished texels + masks + albedo, and
  `python meshy/tools/face_clean.py <npz> <out.png> '<json>'` tries options
  offline (render with keys_zoom.py on raw/<kind>/<kind>.glb).
- Scratch helpers (SP/meshy-work/q): aimview.sh <kind> <out> [cz] (aim and
  fire from 4 sides, zoomed), sheets.sh <kind> <NN> [cz] (make + hands +
  face close-up sheets of the installed build), checks.sh <a,b,c>,
  facetry.sh.

## Sixth session

Order from the coordinator: redos barker 09c, chum_tosser 10d, jerry 19d,
clone 04f, baron 22c; then swamp_king; then the 16 humanoids; then skeeter;
then rudy 20b / maw dryer / alien hand holes / hat-cut rebuilds as credits
allow; check_all quick last.
Recipe per redo: move meshy_out/<kind>_{concept,model,rig} to *_<oldNN>,
meshy-work/add_prompt_<kind>.py ("refs": "cel"), meshy_kind.sh concept
(look), meshy_kind.sh model, kind_config.py (old config kept as
meshy-work/<kind>_<oldNN>.json), meshy-work/iter.sh, SKIP_BUILD=1
finish.sh, actor_check + live_body_check + physics_check (gd.sh), unchurn,
INDEX line, commit.
Done: 09c barker (44 cr; "skin_sat" 1.6 + "colour" 1.4 + "hand_hue" stop
the pale hand tone dithering grey), 10d chum_tosser (44 cr; gloves in flat
paint mode - "hands_paint": "texture" made them flat; "recolour" boxes at
the wrists paint Meshy's cut glove ring into a gauntlet cuff, cap recolour
to red). Credits after 10d: 1,260 of 2,500 (balance 1,678).
10e chum_tosser: shaded gloves ("glove_shade": true + glove_light/
glove_contrast/glove_grime_k; boss and rudy keep the old glove path).
19d jerry (53 cr), then 19e (0 cr) after the coordinator held 19d back
(flat painted face). 19e: "head_noshadow": true (the head's texels from a
second bake per turn with the Meshy mesh casting no shadow: Meshy's facial
shading kept, the helmet/bar shadows gone), "texture": 1024 (bosses may:
maw and swamp_king do), "skin_even" tone [146,94,76] for hands/forearms,
helmet shed refitted (dome cut z 1.80, shell + stripe copied by colour,
mask cut front/sides), scalp recolours.
JERRY STILL OPEN (coordinator's 19d note, do first next session):
 (a) EYES: Meshy's model has squinting eyes (my prompt said "squint"), so
     no whites/pupils show. Fix with credits: a fresh concept (same prompt
     minus the squint: "wide-open eyes with clear whites and dark pupils")
     + model + rig (~53), or a Meshy retexture of jerry_model. A new model
     needs the shed boxes refitted (scripts4/headclass.py gives the helmet/
     skin/grey bounds; headshots.sh with all six helmet_*_gear bones).
 (b) BARE HEAD: still bad - the shell copies SHARE texels with the body
     under them (a recolour of brim yellow turned the WORN helmet brown),
     and shag shrink exposes Meshy's inner scalp (skin) plus shards at the
     ears/back; the hat cap floats as a disc. Needs a real fix in shed.py:
     give copied pieces their own UV island/texels (then the body under
     can be painted hair freely), or build a cropped-hair skull cap from
     the head's inner surface. No red/yellow slivers allowed.
 (c) the face's grey patch over his left eye (the wink eye).
Face options added this session (build_actor): face_albedo (+_shade,
_sat, _hue; flattens the face - do not use for faces with detail),
face_greys, bake_ray, head_noshadow.
clone 04f: DONE (44 cr; balance 1,581, track 1,357 of 2,500). Built with
"head_noshadow": true - without it the hat brim's shadow made the face a
dark smudge again (the owner's complaint). USE "head_noshadow": true FOR
EVERY KIND WITH A HAT, HELMET OR BRIM (cheap: one more bake per turn).
Face close-up: headshots.sh <kind> none <cz> out.png (KV_SCALE .5).
clone open: live probe chest row reads the gun 5.1 cm into the body at one
blended picture (key 7) - look at live/clone_probe/chest.png picture 10.
NEXT SESSION, in order: jerry 19f (eyes + bare head, see above), baron
22c (redo; use head_noshadow - top hat brim), then swamp_king, the 16
humanoids, skeeter, rudy 20b etc. Latest commit: see git log.
Then baron 22c, swamp_king, the 16 humanoids (see the coordinator order).

## Fifth session

THE OWNER'S RULE CHANGED (2026-11-26): the models need not copy the old
ones. Keep each character's role, prop and how it is used, outfit idea and
colours; give a natural, well-proportioned body and a clear, good-looking,
ORIGINAL face (no real person's likeness). Pick the best-looking concept,
do not spend credits chasing old details. Everything else in the bar stays
(gripping hands, rigid gear, stances, arms in hits, palette, sizes, checks).
In INDEX lines say what was kept and what changed for the better.
For a redo or new kind: prompts entry with "refs": "cel" (make_requests.py
then sends the cel alone, not the old model's render, and adds the natural
body / original face note).

Credits: 1,172 of 2,500 spent (balance 1,766). Keep ~150 in reserve.

Done this session: 23 maw, 24 maw_bare, 03h yard_deputy (redo). See INDEX.

ORDER from the coordinator (do in this order):
1. Maw fixes still open: (a) the dryer is too small for her: gear_scale
   [{parts, k, side}] (build_actor, new) grows it - maw_bare takes 1.7x
   cleanly (1 cm), but the housecoat Maw at any k >= 1.25 has the dryer
   15 cm into the wide skirt in the walk keys and keep_out cannot get it
   out (keep_out/depth_in look only 0.14 m deep - absolute, not scaled;
   scaling that by height made it measure 0.35 m false depths: reverted).
   So maw (23) is at 1.0 and maw_bare (24) at 1.7 - inconsistent; fix the
   giant's keep-out (or carry the dryer forward, the old keys held it
   ahead of her) and give both 1.7. (b) pain: "head_keys" {key: [pitch,
   turn, roll]} (new) - [-20, 0, 15] lifts her face back into view (done,
   both). (c) down: she lies on her back face up (checked, keys_views
   angle 0 = front, 180 = back).
2. swamp_king - NOT STARTED (no credits spent). The old model is the King
   (people's skeleton drawn by person()) standing on the airboat (hull,
   bow shield = shoot-off "shield", engine, caged prop, pennant); his
   crown is shoot-off "crown"; dump_actor gives ok=false (the boat's parts
   are labelled legs); fit.json down_cel (the sunk-boat cel). Plan: Meshy
   the King alone (crown over a mesh cap, red airboat muffs, cigar, ginger
   brush beard, gator-hide cape with its head on his shoulder, belly);
   build on the BEAST path with a new "keep_parts" option: fit the Meshy
   King onto the old King's person parts only (P restricted to their
   vertices), weights from those parts only, and keep the old boat parts'
   geometry rigid on their bones with their old texels baked into the new
   atlas (an emission source like build_actor's gear bake, pasted by
   gear mask); shield/crown stay gear names. Check boss_end (the boat's
   fall), arena_wreck (shield, crown), physics, actor_check.
3. Redos (fresh concepts, "refs": "cel"): barker (09c), chum_tosser (10d),
   jerry (19d: heavyset athletic, a clear cocky ORIGINAL cartoon face
   readable behind the face mask - check a zoomed face close-up), clone
   (04f: clean readable face), baron (22c: a real neck and head, readable
   face, the copper rig worn on a portly body). Then the 16 humanoids, then
   rudy if budget. Write each redo into this file too.

New tools/options this session (meshy/tools):
- build_actor: "skin_texels" {hue, sat, val} (a non-human skin: Maw's grey-
  green; the people's skin tests want red > green > blue), "bottle_grip"
  (share of the length from the end where a "bottle" item is gripped: .08
  takes a rolling pin by its handle), "gear_scale", "head_keys", an empty
  "shed": {} clears the old model's gear names.
- A hand with fewer "fingers" leaves open holes where the others were cut
  (black triangles up close): Maw has five; the alien (05b, three) may
  show the same up close - check its hands sheet large.
- make_requests: "refs": "cel", "extra_refs" [paths under SP] +
  "extra_note" (one face across two models: maw_bare used maw's concept).
- hands_sheet.sh crop grows with the kind's height; tour_for.py: giants
  (maw, maw_bare, swamp_king) shot on Hickston's open street, view tipped
  up; ingame.sh maw 9.0 (and pass "old" to re-shoot the old side).
- Engine (branch): ActorLayer3D.kind_of draws Maw as "maw_bare" under a
  third of her health and in her fall (before, the 3D view never showed
  the bare set: it stripped "bare_" and drew the housecoat model); main.gd
  view tour takes an actor "hp" share. fit.json maw/maw_bare: down_cel off,
  hand_over false (her model's fall, as the baron).
- Maw's dump is patched: scratch `meshy-work/scripts4/maw_fallfix.py`
  rewrote dump/maw_poses.json's die/down torso points from her grey body
  (b0) - the old falls were drawn in the bare set and the housecoat
  anchors stood still (original kept as maw_poses_orig.json). Both Maws
  build from this dump and maw's old glb.
- Scratch probes (meshy-work/scripts4): handdark.py / handdark2.py (hand
  faces on dark texels), handwind.py (flipped hand faces), hueprobe.py
  (built-model faces by graded colour in a z band), meshyhsv.py (Meshy
  model faces by Meshy colour in a build-space box: use it to pick shed
  hue windows), q/strip2.py (tile keys_views output). keys_zoom.py now
  deletes KV_HIDE pieces' vertices (Blender 5 put muted scales back).

## Fourth session


Done: 18c/17c quick fixes (steeper carry "carry_dir"/"carry_at": revenue
man's both hands on the gun; spectacle rim painted over "rim_px"; sheriff
"clearance" .05), 19b/19c jerry, 20 rudy, 21 foreman, 22 baron (baron has
open items: brim spikes, monocle ring/chain left, right fist off the
nozzle - see INDEX 22). Credits now 995 of 2,500 (balance 1,943; jerry took
three concepts). Paid calls one at a time.
More options from 21/22: build_actor "gear_force" (old parts held although
the old body keeps them at "down": the foreman's blade), "hand_hue" [lo,hi]
(hand skin matched only to skin of that hue: hard hats, beards and copper
made hands yellow); shed "rim_hue" (paint a gold rim by hue), hat
"even_rim": false for a flat brim crossing the cut. Old held parts that
are gold/white pass for the old hands: give "grip_parts" (find the old
hand parts nearest dump points 6/8). "hold" item type follows the old
keys exactly (used for the baron's nozzle and jug; "pistol" made a mess of
his aim/fire).

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

22b: the baron's jug is held by the neck ("bottle") in every key (the
coordinator saw the hand flat on the jug's side in the swig with "hold").
drone (checked): an alien worker "grey" (enemies.cfg [drone]: millhand
brain, melee lunges, 1.52 m tall, voice "grey") - a humanoid for
build_actor like the alien (05b).

Left, in order: maw (+maw_bare: same model, plates on, 4.4 m tall - a
giant; check its size rules in actor_check), swamp_king (on his airboat:
keep the boat as old gear or the beast path); then the
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

Last check_all quick (fourth session, after 22b, scratch profile): 53 ok,
1 FAILED - cpu_check "the bot game's tick 2.06 yardsticks (< 2.0)" under
check_all's parallel load; cpu_check run alone right after: CPU CHECK OK
(1.14 yardsticks). actor_check, boss_check, boss_end_check,
boss_rematch_check, arena_wreck_check, live_body_check, physics_check all OK
after every boss of this session (run alone).

Last check_all quick (fifth session, after 03h and the maw fixes, scratch profile): ALL CHECKS OK (54 checks listed ok, 153 s).

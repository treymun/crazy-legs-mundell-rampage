# Meshy models track: handover (2026-11-26, eighth session)

Read `meshy/README.md` (method) and `SP/meshy-previews/INDEX.md` (every
version, every decision) first. SP = the session scratchpad.

## Eighth session (read first, then the seventh)

27 swamp_king DONE (44 cr: concept, model, rig). Built on the BEAST path
(build_beast.py, kinds/swamp_king.json): the Meshy King fitted onto the old
King's parts only, the airboat, punt gun, gig and crown kept exactly as the
old parts (rigid on their bones, old texels pasted - gear_paste.py puts them
back after the grade, as for people's gear). New build_beast options (all
opt-in; nothing changes for the animals):
- "keep_parts": list, or {"except": [bones]} - old parts kept as they are;
  the fit and the weights use the other parts only. Written: <kind>_gearmask
  / _gear / _gear_p2 / _gear_p3.png (old texels by an EMIT bake through the
  old UVs; NOTE: a re-linked old Material Output baked black - a fresh
  output node is made). "kept_uv" (.6: kept islands drawn smaller before the
  pack), "hand_uv" (1.5), "uv_margin" (.003), "bake_margin" (3 px; keep it
  with uv_margin or seams bleed as red dashes).
- "fit_skip" (bones out of the fit only), "fit_scale": "z" (scale by height
  alone).
- "pose_arms" {side: {upper, fore, hand, elbow_shift}}: a RIGGED Meshy glb's
  A-pose arms bent (its own weights, two bones, the elbow toward the old
  elbow) onto the old arm parts at the standing key, before the weights.
  The Meshy groups are cleared afterwards (left on they rode no old bone and
  dropped vertices to the origin).
- "grip_hands" {side: {gear [bones], palm [x,y,z], cross deg, along} |
  {curl}}: Meshy's mitten cut off, a hands.py hand put on (palm toward the
  held part's axis, crossing it at least "cross" degrees, wrap_curls), rigid
  on the old hand bone (the wrist blends from the old forearm bone); its
  look the sculpted hand's painted skin turned to the Meshy hand's colour,
  baked lit with the body. "hand_share" caps its length.
- "merge" {bone: [bones]} (old blocks weighted as one), "arm_reach" k (an arm
  vertex farther than k x the posed Meshy arm's girth from its bone goes to
  "reach_to": the cape flapped with a raised arm), "reach" {bone: m} (by the
  old part's axis; not used: the Meshy forearm is off the old block's axis).
- "attach" [{chain [upper, fore, hand], parent, ride}]: the old block arms
  turn about their own middles, so a raised arm tore the smooth skin at the
  shoulder; each key re-made so every part meets the one above at its
  joint. "ride": bone - in the live keys the hand rides that part exactly as
  at the standing key and the arm reaches it by two bones (the fist never
  leaves the punt gun in aim/fire/pain); the falls use the plain attach (the
  gun flies off).
- "keep_fit" [{bones, scale, drop|move}]: kept parts re-seated (the crown
  0.82 and 6 cm lower onto the new head).
- "phases": a boss's p2/p3 looks written (soot blotches, front blood; kept
  parts take the old phase looks' texels). "gain" multiplies the matched light.
- The build prints "BEAST texels a metre" (actor_check's measure; boss >= 90).
Known on 27: the Meshy legs are a stocky man's, shorter than the old block
legs (he reads a little squat mid-stride); a raised arm in pain/die still
pulls a short wing of vest under the armpit; the old gun/boat texels are the
old low-res ones. Sheets 27_swamp_king_make/ingame/face.png.

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

PROGRESS (seventh session, all committed with INDEX lines): 04g clone,
long-gun sweep (01l billy, 06c big_billy, 18d revenue_man; coot/drunk_coot
hold short guns one-handed), 19f jerry, 22c/22d/22e/22f baron (22f: fringe
shaded as hair, temple patches gone; its top edge still a crisp band - the
coordinator said keep 22e if the time-boxed pass did not land; let them
pick), 25/25b boilerback, 26 chain_hand. check_all quick after this batch
(scratch profile): ALL CHECKS OK in 184.8 s. A's ledger: 1,498 of the 2,007 budget (record
each call at its LIST price - concept 9, model 30, rig 5 - and note any
bigger balance drop: B spends on the same account at the same time).
NEXT, in order: (1) 26b chain_hand (coordinator): a chain with visible
links that hangs and swings - a Meshy chain prop (<= 20 cr) or a modelled
link chain as a held_model with "tails" (the catfish's HeldTail flop:
meshy/assets/catfish.glb and noodler.json are the example), draping from
the fist in idle/walk, trailing in the wind-up, whipping on the lash, the
hit still on the lash key; fist grip and 0 cm clearance kept; and warm his
grey ears to the skin. Started: meshy/tools/chain_make.py makes a 24-link
0.86 m iron chain glb with a big grip ring at the front end (held_model
finds the front as the wide end; `blender -b -P meshy/tools/chain_make.py
-- <out.glb>`; rendered fine, NOT yet tried in a build). Try "held_model"
{"glb": <chain>, "length": .86, "tails": [.25, .45, .65, .85], "grip":
.03} with item_types r "bottle" (the catfish path hangs it plumb in
carry/walk and swings it on wind/fire); the ears: they fall outside the
face zone's skin test (grey, low saturation) - widen with face_box or
paint them. (2) swamp_king (plan in the fifth-session section;
NOT started, 0 credits). (3) chalk_spitter, flagman, gas_man (refs in
SP/meshy-work/ref/<kind>_front/side.png; cels assets/art/<kind>_0.png:
chalk_spitter a chalk-white ghoul 1.38 m who spits chalk, flagman a
railroad flagman - red cap, white moustache, black vest, white shirt,
green flag in the left hand and an orange flare in the right, gas_man an
olive gas-masked trooper throwing tear-gas canisters, brain
bottle_tosser). Then tell the coordinator, who assigns the leftovers.
Per minor model: make/hands/face sheets (SP/meshy-work/q/sheets.sh), live
probe rows, actor/live_body/physics checks; no in-game sheet. Check-all
quick once per ~4 models (last: after 26 chain_hand, ALL OK).
Order from the coordinator's last note: swamp_king, then chalk_spitter,
flagman, gas_man, and the 26b chain fix.

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
- face_clean more options: "cloth_hue" (55; albedo hues above it up to
  320 are cloth - jerry 36 for the yellow helmet), "max_sat" (a red
  jersey), "white_k"/"ring_k" (eye whites lighter than white_k x the
  face's middle; the ring round them only where darker than ring_k - the
  baron's white whiskers made his face grey), "keep_white": k (white
  whiskers below the eye line keep their own look), "paint_hue" {hue, sat,
  to, grow} (that colour in the upper face painted `to`: the helmet's edge
  Meshy painted on jerry's forehead). Zones (face_box): front above
  "eye_z" (.07) = upper (whites looked for there only), below "chin_z"
  (-.01) = chin (pale grey paint there - mask bars - is skin), behind the
  ears up to "back_top" (.08) = skin only. Face box r: .17 suits a normal
  head; jerry and the baron (big heads, Head bone far back) need r .27-.3
  (face_uv r too) - check "face islands favoured" and the face zone.
- "hi_texture": a painted copy of the Meshy base colour used for the bake
  (jerry: open eyes painted by meshy/tools/eyes_paint.py:
  `blender -b -P meshy/tools/eyes_paint.py -- <rigged.glb> <out.png>
  '{"eyes": [[-0.0525, 1.664], [0.0525, 1.664]], "w": 0.021, "h": 0.0085,
  "iris": 0.0068, "pupil": 0.0032, "look": [0, -0.12]}'` - eye places in
  the RIGGED glb's own space, found from a front render of it; the png is
  scratch at SP/meshy-work/paint/jerry_tex_eyes.png - re-run that line if
  it is gone).
- shed.py: box rules "except" [{hue,sat,val}] (take every face in the box
  but those colours; the hue window is not used) and "fill" (rings: left-out
  faces mostly surrounded join) - jerry's whole shell, no islands; "ring"
  {at, r, tube, normal, paint, lens_paint, lens} - a piece MADE, not cut
  (the baron's monocle: a gold ring, paint ids 20/21 coloured by kind
  "paint"). The copies of a box rule already get their own UV islands (the
  shed runs before the unwrap); jerry's brown worn helmet came from the
  position-based recolours.
- More options (later this session): "item_holds" {gear index: {side:
  share}} (who holds a thing, by hand); "carry_both" (the other hand on a
  two-handed thing in the stand/walk/carry keys); "cheek_pitch_max" (cap
  the weld's head pitch: the boilerback's visor faced the camera);
  face_box/face_uv {"auto": true} (zone centred from the face itself, set
  back 11 cm - USE IT for every new kind; the Head bone can be 30 cm
  behind the face); face_clean "sat_k" (pale skin dithered grey-teal: 1.45
  on chain_hand). shed hat rule: "cap_skin" (true = face skin, or a
  colour) + "cap_fringe" {colour, height, front_deg} (bald pate with a
  soft-edged fringe round the sides and back), "sliver_in", "band_in"
  [depth, k, back_only] (under-brim hair spikes drawn in); "head_keys" set
  [0,0,0] for 0/walk/fidget/recover when the old head pose stares down.
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

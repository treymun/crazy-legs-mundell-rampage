# Meshy models (pass 16 track, branch `meshy-models`)

Every character remade with Meshy, then turned into the game's own actor
format by Blender, so every animation, the living body and the ragdoll work
with it. Not merged: the main line takes it after pass 15 ships.

## Steps for one kind

1. **Concept and model (credits).** `tools/make_requests.py <kind>` writes the
   request bodies from `kinds/prompts.json` (the old model's front render and
   its cel as references, A-pose, empty hands). `tools/meshy.py run ...` runs
   image-to-image (9), image-to-3d with `pose_mode: a-pose` (30) and the
   auto-rig (5). The key is read from `~/.clmr/meshy_key.txt` at call time,
   never stored; every paid call is in `credit_ledger.json` with the balance
   before and after; the cap is 2,500 for the track.
2. **The old model's motion.** `godot/tools/meshy/dump_actor.gd` dumps the
   current model's rig points and bone poses at every key (run on the
   untouched tree).
3. **Build.** `tools/build_actor.py` (Blender) with `kinds/<kind>.json`
   (`tools/kind_config.py` writes it):
   - the Meshy mesh sized to the old height, decimated to ~10k triangles,
     its Meshy weights merged to one bone a body piece, stray weights dropped;
   - Meshy's mitten hands cut off and replaced by `tools/hands.py` hands:
     palm, four fingers and a thumb, three bones each, knuckles and nails,
     skinned, sized to the Meshy hand, their skin matched to the body's;
   - a flat skeleton, each bone's origin on a ragdoll point (actors.json
     `joints`, `segs`), every old key posed anew: the torso, head, legs and
     free arms from the old key's rig points (two-bone IK, anatomical
     hinges), a two-handed gun **authored** for the body (the carry across
     the body, a shouldered stance searched to fit the body, the pain drop),
     the hands put on the gun with straight wrists and the fingers closed on
     it (`hands.grip_curls`);
   - each held thing cut off the old model, kept as its **own unskinned
     mesh** hung off a bone (Godot: BoneAttachment3D), kept out of the body
     in every key (`keep_out`, 2 cm clearance), dropped as a piece on death;
   - a dusk-stage bake (four turns), the skin hue fix and the light matched
     to the old look, a hurt look.
4. **Install.** `tools/install.sh` (grade, pack, import, bake rigs).
5. **Previews and checks.** `tools/finish.sh <kind> <NN>`: the make sheet
   (Blender turnaround, rig, keys, hands close up), the in-game sheet (old vs
   new, day and night, hands crop), `live_frames.gd ... probe` (how deep a
   held thing goes into the body over the reactions) and the death rows;
   `tools/make_video.py` for the motion clips.

Engine changes the models need (all in this branch): RagdollRig reads
`joints`, `segs`, `rides`, attached held meshes and `holds`; LiveBody keeps a
gun hand from clutching; ActorView thrusts a held gun clear when knocked down;
rig_reference.gd follows; live_frames.gd and death_frames.gd take `kind=`.

# Art

The art in `assets/` is made by the Godot art tools in `godot/tools/art/`
(GDScript, run like the other tools), with Blender for the 3D renders and the
3D models (`scripts/blender/`, run inside Blender's own Python). After any of
them, run `tools/pack_assets.gd` (and `--import` after new `.glb` files).
`paint.gd` is their drawing library. Each takes `out=<dir>` to write somewhere
else for a comparison. Their pictures have the old Python builders' look, not
their exact bytes. Every picture is committed to the VGA palette.

## The 2D art builders

| Tool | What it makes |
| --- | --- |
| `build_fx_art` | the soft older effects (also runs gore, menu, building tiles) |
| `build_gun_fx_art` | the LIGHTS AND GLOW muzzle flashes, blasts, soot, scraps, dust ring and strikes (below) |
| `build_gore_art` | gore pictures (it rewrites the older gore pictures slightly differently: put those back after a run) |
| `build_menu_art` | menu boards and pictures |
| `build_building_tiles` | building wall tiles |
| `build_town_signs` | Hickston's painted signs and the corn tile |
| `build_bayou_art`, `build_speedway_art`, `build_ship_art` | each new chapter's tiles, sky or signs; the Mothership's alien-lettered signs and Maw's floor marks |
| `build_quest_art` | every chapter's quest props (below) |
| `build_town_props` | every chapter's modelled props as sprites (below) |
| `build_enemy_actors` | the enemy and boss cels: runs Blender, then shrinks, grades and digitizes its renders |
| `build_weapon_views` | the first-person guns: likewise; also cuts the throwables' flight pictures (`fx_<name>`) |
| `build_hit_art` | hats knocked off (`fx_hat_*`) and dropped weapons (`fx_drop_*`) |
| `build_break_art` | signs' `<name>_shot` and the bits `fx_brk_*` |
| `wall_break_art` | the broken window tiles `<material>_brk` |
| `build_impact_art` | holes, blood runs, wall scorches, splinters, grit and glints (features/impacts.gd) |
| `build_world_fx` | brass, hulls, embers, ground scorches, crows, fireflies |
| `build_county_art` | County Run's XP bottle caps `county_xp_<tier>_<n>` |
| `build_item_art` | the armory's wall pictures of guns with no pickup picture (`item_<name>`, via `item_pictures.py`) |
| `build_range_signs` | the firing range's signs |
| `enemy_sheet` | `-- dirs=<old>,<new>` lays cels side by side (`docs/enemy_art/`) |

CI runs `build_fx_art`, `build_building_tiles`, `build_menu_art` and
`build_gore_art` into a scratch folder to check they still run.

### Quest props

`build_quest_art`: every chapter's quest props, modelled in Blender by
`scripts/blender/quest_props.py` as freestanding props that read from any
side: control boxes on posts with a throw lever, the relay cabinet, brake,
bell, exit signal posts, valves, the bayou's generator and ignition, the
speedway's fuel dump and flags, the Mothership's consoles. Each station is
`town_quest_<name>_off` (lamp lit, lever up) and `_on` (lamp dark, green
pilot, lever thrown and tagged), cropped to one frame; the keys and the PA
patch lead are rendered pickups; and, painted, Hickston's pen sign, the
locked gate's barricade, the Crossroads' later gate boards and markers, the
fingerpost's arms and the beam pad's order: signs, not stations.

### Town props

`build_town_props` runs `scripts/blender/town_props.py`, which execs
`props_more.py` and each chapter's `props_<chapter>.py`, then
`props_range.py`: every chapter's modelled props, `town_<name>`, their sizes
in `assets/art/town_props.json` for the level builder's `town()`. Broken
props come from `scripts/blender/props_broken.py` through the same tool
(breakables, [gameplay.md](gameplay.md#things-break)). `no-render` reuses the
last renders; `names=` picks some.

### Enemies and bosses

`build_enemy_actors` renders each kind on the dusk stage, with wind-up, hurt
and boss phase cels ([bosses.md](bosses.md#the-bosses-art-wears-the-fight)).
`kinds=billy no-render` re-cuts one kind from the last renders;
`frames=headless` renders the headless down cels (render to a scratch raw=
and out= and copy only the new files). The variants are in
`scripts/blender/actors_variants.py`, the wounds in `actors_wounds.py`, the
later chapters' kinds in `actors_bayou.py`, `actors_speedway.py`,
`actors_mothership.py`. The chicken, pig and Bessie are not Blender actors.

Mundell himself (`actors_mundell.py`, kind `mundell`: no cels, only the model
the 3D view draws for the other players) is a `person()` cast with wrapped
head, body, legs, arms and weapon: the face, brow, nose and beard are balls whose
vertices carry a `face` texture coordinate onto his front picture
(`player_front_0`, the face's box `_FACE_BOX`) and a `face_w` weight fading it
into plain skin and beard round the sides (`photo_mat`), so the bake carries
the photograph's face onto the model; export_actors.py drops those layers from
the joined mesh before its own unwrap. Olive cap with the tan patch, grey
beard, a big red and black check (`plaid_size`, `sleeve_plaid`, darkened by
`_checked`) over an orange tee, slim sleeves, denim bib overalls with the
thigh patch, brown boots, the pump gun with three brass shells held low
across his hips in hands whose fingers close round it (open when off it),
all from that picture; head and face get more of the texture (`uv_head`,
`uv_face`, export_actors.py `_favour_head`); `enemy_actors.py -- <dir> mundell
0,quarter_0,side_0,away_0,back_0 2` renders him to hold against the player
pictures.

## The 3D asset pipeline

The 3D view draws props and enemies as models made from the same Blender code
that renders their sprites, so they match the old cels. Faces, hands and
colours must look right and match the cels before a model counts as done.

### Props

1. `scripts/blender/export_meshes.py` bakes each prop (a COMBINED light bake
   under the dusk stage) to glTF.
2. `tools/art/build_prop_meshes.gd [-- names=outhouse,tractor] [no-render]`
   grades (`Paint.photo_grade`) and digitizes each texture to the palette
   (`assets/art/mesh_<name>.png`, packed with the rest of the art) and writes
   `godot/assets3d/props/<name>.glb` plus `meshes.json` (sizes, read by
   `view3d/prop_models.gd`).
3. `tools/pack_assets.gd`, then `--import`.
4. `tools/art/build_prop_scenes.gd [-- names=a,b]` writes
   `scenes/props/<name>.tscn` (a `PropView` root over the glb instance, so a
   new export shows through). Open a scene in the editor to add to it (a lamp,
   a flame); it keeps those when the tool runs again only if the prop is
   skipped (`names=`).

There are 194 props.

### Actors

1. `scripts/blender/export_actors.py` rigs every enemy and boss from the same
   per-frame Blender builds that render the 2D cels (parts matched by shape
   fingerprint, bones by identical motion), keys every frame at 24 fps in
   action "poses", labels bones head/arm_r/arm_l/leg_r/leg_l/body, and bakes
   looks (plain, hurt, p2, p3) under the dusk stage.
   - Matching: parts pair in order within an exact print, then a left-over
     part takes the nearest left-over print within `NEAR` (10%: a scale
     rounded differently as the torso turns, a shin stretched by the walk,
     fingers curled in a fall), nearest to where it sits on the body. Before
     this, a third of Big Billy's parts (his belly among them) vanished for
     his fall, and a boot for one walk beat.
   - A part missing from a key (the gun once he is dead) is shrunk where it
     is in the nearest key it is blended with (walk beats, fall steps), or,
     missing from all of them, shrunk into the body's biggest bone; never
     left where it stood, so nothing hangs in the air over a corpse. Keys
     are LINEAR. A frame of other parts altogether (the derby champ's wreck)
     holds the rest where the frame before had them.
   - `view3d_check` fails a kind with a part (shrunk or not) higher than
     half its height (or half a metre) at the key "down", or a part partway
     shrunk at any key (both were in every v3.0.0 kind: County Run's
     floating bits after kills).
   - The unwrap (`_unwrap`): smart project, then the islands packed by their
     shapes with a gap of `GAP` (.002 of the texture). With smart project's
     own .01 gap a boss's hundreds of rivets, each cut in several islands,
     took nearly all the texture in gaps: the baron's islands covered 3% of
     it, Jerry's 4%, Billy's 14%; packed, about half (four times the texels
     across on the baron), so faces and bellies are no longer a few blocky
     texels. Only kinds baked since have it (the baron).
   - Looks are 512² (`TEXTURE`); `FINE` kinds bake 1024² (the baron), with
     fewer samples a texel.
2. `tools/art/build_actor_meshes.gd [-- kinds=billy,coot] [no-render]
   [rig-only] [raw=<dir>]` grades and digitizes
   (`assets/art/actor3d_<kind>[_<look>].png`) and writes
   `godot/assets3d/actors/<kind>.glb` plus `actors.json` (each kind's frames
   and looks, read by `view3d/actor_models.gd`). `rig-only` makes the mesh
   and rig again without baking (a minute for every kind instead of hours):
   the unwrap is not the same run to run, so the committed model's unwrap is
   carried over face by face and its looks still fit; use it for a change to
   how a kind moves, not to its parts. `raw=` puts Blender's output
   elsewhere than `_preview/actors/mesh_raw` (two runs at once). It keeps
   each `.glb.import` at `animation/fps=24` (the keys' own rate; at Godot's
   30 the keys were resampled between and a part shrunk away in one key came
   back half-grown in mid-air: Big Billy's fall specks); `view3d_check`
   fails a kind that is not.
3. `tools/pack_assets.gd`, then `--import`.
4. `tools/art/build_actor_scenes.gd [-- kinds=a,b]` writes
   `scenes/actors/<kind>.tscn` (an `ActorView` root). Same rule as props for
   hand additions.

How ActorView poses and picks a look is in [view3d.md](view3d.md#actors).
Guns in hand stay 2D cels over the 3D view.

`tools/view3d_check.gd` loads every prop and actor scene; run it after either
pipeline.

## Gun effects art

`tools/art/build_gun_fx_art.gd` makes the pictures for the LIGHTS AND GLOW gun
and blast layer (`features/gun_fx.gd`, `gun_flash.gd`; see
[gameplay.md](gameplay.md#gun-effects)): hard edged, few colours, committed to
the VGA palette; `fx_mf_*`, `fx_boom_*`, `fx_soot_*`, `fx_chunk_*`,
`mark_shock_*`, `fx_hit_*`. Each gun has a flash style (STYLES; the 5v5 guns'
are hunter, mower, auto45, magnum, pump, smg, bar, marksman).

`tools/gun_frames.gd` renders every gun firing at a plank wall, a blast, a
chain and the .38 into each material, in a window, as rows of frames (run it
on the old build too for a before; `docs/weapon_fx/` has the contact sheet):

```
godot --path godot --audio-driver Dummy --resolution 1280x800 --script res://tools/gun_frames.gd -- out=<dir>
```

## Guns in first person

`scripts/blender/weapon_views.py` models every gun (the plates' rigs: the
revolver plate, the shotgun plate, the crowbar plate for throwables), cut by
`build_weapon_views.gd`. The 5v5 guns' side materials and `pbr(edge=,
cavity=)` are in [modes.md](modes.md#the-guns). `src/melee_blood.gd` wets the
crowbar and sling blade (a cached copy of the graded cel in weapons.gd).

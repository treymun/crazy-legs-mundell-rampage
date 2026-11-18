# Art

The art in `assets/` is made by the Godot art tools in `godot/tools/art/`
(GDScript, run like the other tools), with Blender for the 3D renders and the
3D models (`scripts/blender/`, run inside Blender's own Python). After any of
them, run `tools/pack_assets.gd` (and `--import` after new `.glb` files).
A chapter enemy's art and model, and a prop only one chapter shows, go in
that chapter's browser pack by themselves; a new model of a chapter enemy or
such a prop needs `tools/pack_check.gd -- fix` to write it into the browser
presets' list ([checks.md](checks.md#the-browser-packs)). The browser and
phone builds halve model textures over 512 texels a side (`pack_lite.gd`).
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
| `build_bayou_art`, `build_speedway_art`, `build_moonshine_art`, `build_ship_art` | each new chapter's tiles, sky or signs; the Mothership's alien-lettered signs and Maw's floor marks; the Moonshine Run's woods, bluff and cave floor tiles, its moonlit sky, its signs and the tear gas canister in flight |
| `build_quest_art` | every chapter's quest props (below) |
| `build_town_props` | every chapter's modelled props as sprites (below) |
| `build_enemy_actors` | the enemy and boss cels: runs Blender, then shrinks, grades and digitizes its renders |
| `build_weapon_views` | the first-person guns (all but the crowbar; the .38's and sawed-off's models in `weapon_plates.py`): likewise; also cuts the throwables' flight pictures (`fx_<name>`) |
| `build_hit_art` | hats knocked off (`fx_hat_*`) and dropped weapons (`fx_drop_*`) |
| `build_break_art` | signs' `<name>_shot` and the bits `fx_brk_*` |
| `wall_break_art` | the broken window tiles `<material>_brk` |
| `build_impact_art` | holes, blood runs, wall scorches, splinters, grit and glints (features/impacts.gd) |
| `build_world_fx` | brass, hulls, embers, ground scorches, crows, fireflies |
| `build_county_art` | County Run's XP bottle caps `county_xp_<tier>_<n>` |
| `build_weather_art` | prints in the mud: `mark_boot_mud`, `mark_hoof_mud`, `mark_claw_mud`, `mark_tyre_mud` |
| `build_item_art` | the armory's wall pictures of guns with no pickup picture, and the crowbar's, .38's, sawed-off's, dynamite's and dynamite sticks' pickups (`item_<name>`, via `item_pictures.py`) |
| `build_range_signs` | the firing range's signs |
| `build_vehicle_signs` | the hand-painted KEYS IN IT signs left by the vehicles (`vehicle_sign_airboat`, `_car`, `_mower`: letters a pixel up or down, paint running, a key on a ring; sun-bleached bayou planks with a bite out, a checkered tin plate, the church's whitewash) |
| `build_gun_signs` | what points a player at a gun not had yet (feature pass 7, `src/gun_finder.gd`), in the vehicle signs' hand: every word at least twice its size so a line reads from a few cells off: GUNS THIS WAY sawn to an arrow (`gun_sign_way_r`), Hickston's GUNS / HONOR SYSTEM with a rifle painted by it (`gun_sign_honor`), the fair's WIN A GUN / NO REFUNDS on striped tin (`_fair`), MILL LEAGUE / BOWLING NITE on grey tin (`_mill`), DANGER / COW LAUNCHER / NOT YOU MUNDELL on hazard tin (`_quarry`), a hobo's chalk gun and X (`_chalk`, the wall showing through); the glint over a gun lying out (`fx_gun_shine_0..2`: spark, cross, star); Mundell's shadow board for the trophy shack (`gun_board`: pegboard, a whitewash outline of each `GunFinder.BOARD` gun from its pickup picture, MUNDELL'S IRON in the last place) |
| `build_bench_art` | Mundell's junk bench (content pass 8): the screen's board `bench_board` (pegboard, a two-by-four frame, MUNDELL'S JUNK BENCH lettered on duct tape, the scrap's coffee can, the foot's tape strip), each mod's manila price tag `bench_tag_<short>` (and `_dim`) with the part rendered on it and its name and line hand lettered, each gun on its pegs `bench_gun_<gun>` (and `_bare`, its whitewash outline), the ON stamp, the HUD's marks `bench_mod_<short>_hud` and nut, the scrap pickups `item_scrap_bolts/wire/hubcap`; the parts, guns and scrap are rendered by `scripts/blender/weapon_mods.py items` |
| `enemy_sheet` | `-- dirs=<old>,<new>` lays cels side by side (`docs/enemy_art/`) |

Redrawn in polish pass 9 (each with a dice of its own, so the chapter's
other tiles, sky and signs come out byte for byte as they were): the
speedway's `tire_wall` (was white and black ovals that read as eggs: now
tyres laid flat in stacks, the tread's slanted blocks and middle groove,
painted white and left black by turns, the paint flaking, clay thrown up)
and the ridge's `ridge_rock` (was a grid of black joints and bedding lines
that read as brick: now sandstone beds of every thickness, each lip lit and
a soft shadow under the next, a few wandering joints, honeycomb pits, moss,
lichen, drawn with `Paint.cloud_seamless` so it tiles without a seam;
`RIDGE_DICE_AFTER` puts the chapter's dice back where the old drawing left
them). `hub_patch` (the Crossroads' patched concrete, no builder: it came
from the Python game) had its long crack and the middle of its seam healed
by hand, so a yard of it no longer shows a grid a cell wide. `Paint.cloud`
does not tile (its grids are blown up without wrapping); use
`cloud_seamless` for a new tile.

CI runs `build_fx_art`, `build_building_tiles`, `build_menu_art` and
`build_gore_art` into a scratch folder to check they still run.

The Moonshine Run's own models: `scripts/blender/props_moonshine.py` (the
revenue cruiser with its light bar, the barricade and its broken copy, the road
flare, the wall tent, the radio mast, the hung lantern, Granny's big still with
the dynamite wired to it), its stations in `quest_props.py` (the shine crate on
its hand truck, the church bell rope, the revenue radio, Granny's dinner iron,
the last jar) and its people in `actors_moonshine.py` (the revenooer, the still
buster, the gas man and the Revenue Man, who bakes at 1024: `FINE`).

### Quest props

`build_quest_art`: every chapter's quest props, modelled in Blender by
`scripts/blender/quest_props.py` as freestanding props that read from any
side: control boxes on posts with a throw lever, the relay cabinet, brake,
bell, exit signal posts, valves, the bayou's generator and ignition, the
speedway's fuel dump and flags, the Mothership's consoles. Each station is
`town_quest_<name>_off` (lamp lit, lever up) and `_on` (lamp dark, green
pilot, lever thrown and tagged), cropped to one frame (the 3D view draws
both as one model: [Props](#props)); the keys and the PA
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
last renders; `names=` picks some. `props_hazards.py` (content pass 8) is
the county's hazards: `wood_chipper`, `bug_zapper`, `electric_fence`,
`well`, `cattle_guard` (sprites, meshes and scenes like the rest).

`tools/art/build_boot_views.gd` (runs `scripts/blender/boot_views.py`) cuts
Mundell's kick in first person, six cels `fx_boot_kick_0..5` (4 and 5, pulled
back and lifted, since polish pass 9): a work boot
modelled from hulls (lug sole and heel, stitched welt, toe cap, eyelets and
crossed laces, tongue, collar) in his model's brown, coming up sole first
from the bottom of his view (chevron lugs, a separate darker stacked heel,
the toe up), with his overalls' turned-up cuff under the heel,
lit by the gun views' three suns, graded as the gun cels; where each sits on
the view goes to `assets/art/boot_views.json` (`brawl_looks.gd PLACES`, held
the same by brawl_check). The game's view is the top 156 rows of the 200 it
is rendered over: keep the boot above row 150.

### Enemies and bosses

`build_enemy_actors` renders each kind on the dusk stage, with wind-up, hurt
and boss phase cels ([bosses.md](bosses.md#the-bosses-art-wears-the-fight)).
`kinds=billy no-render` re-cuts one kind from the last renders;
`frames=headless` renders the headless down cels (render to a scratch raw=
and out= and copy only the new files). The variants are in
`scripts/blender/actors_variants.py`, the wounds in `actors_wounds.py`, the
later chapters' kinds in `actors_bayou.py`, `actors_speedway.py`,
`actors_mothership.py`, the livestock (cow, mule) in `actors_farm.py`. The
chicken, pig and Bessie are not Blender actors. The cow is a 3D model too
(export_actors.py sets `FOR_MODEL`: built square to her heading, not turned
for the camera, and lying `down` flat on her left side with her stiff legs
out, the top pair raised); her `down` cel is turned more to the camera than
she walks, so her legs show their length. The 3D view tips her standing
model over onto that side (fit.json `tips`, [view3d.md](view3d.md#actors)).

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

His pictures lying down (`assets/art/player_down_side`, `_head`, `_feet`, for
a player down drawn flat: [modes.md](modes.md#presentation)) are the model's
own down frame drawn by the game's 3D view: `tools/art/build_player_down.gd`
(a window: `godot --path godot --audio-driver Dummy --resolution 1280x800
--script res://tools/art/build_player_down.gd`) draws the view twice on the
crossroads at HD with SHADOWS off, with and without the body, takes the
difference as the matte, cuts the box, scales it by `SCALE` (about 122 rows a
map unit, `ModeScreens.DOWN_ROWS`), lifts its colour (the dusk view is darker
than the old painted cels; most from the feet, where the body is mostly its
own shade) and gives it the old cels' one-pixel dark rim. The end views are
taken from higher and looking further down (`VIEWS`), so they read along the
body (boots, overalls, plaid, cap) rather than as two soles. Run it again after the model changes, then pack_assets.

## The 3D asset pipeline

The 3D view draws props and enemies as models made from the same Blender code
that renders their sprites, so they match the old cels. Faces, hands and
colours must look right and match the cels before a model counts as done.

### Props

1. `scripts/blender/export_meshes.py` bakes each prop (a COMBINED light bake
   under the dusk stage) to glTF, its lowest point on the ground (the sprite
   was cropped to it). Libraries: `town_props.py`, `props_range.py`,
   `quest_props.py` (the stations) and `painted_boards.py` (signs whose face
   is a 2D tool's picture, given a tin body: `line_sign`).
2. `tools/art/build_prop_meshes.gd [-- names=outhouse,tractor] [no-render]`
   grades (`Paint.photo_grade`) and digitizes each texture to the palette
   (`assets/art/mesh_<name>.png`, packed with the rest of the art) and writes
   `godot/assets3d/props/<name>.glb` plus `meshes.json` ([width, depth,
   height, texture size, the height its picture was drawn at], read by
   `view3d/prop_models.gd`).
3. `tools/pack_assets.gd`, then `--import`.
4. `tools/art/build_prop_scenes.gd [-- names=a,b]` writes
   `scenes/props/<name>.tscn` (a `PropView` root over the glb instance, so a
   new export shows through). Open a scene in the editor to add to it (a lamp,
   a flame); it keeps those when the tool runs again only if the prop is
   skipped (`names=`).

There are 228 models: 227 for 253 of the 257 `town_*` pictures, and
`shop_lamp` (props_more.py) for the old hanging lamp picture `prop_lamp`
(`PropModels.PICTURES`). The range's four targets (`range_target`, `_gong`,
`_cow_target`, `_duck`) stay pictures (`KEEP_FLAT` in export_meshes.py),
drawn as slabs ([view3d.md](view3d.md#slabs-pickups-loose-things-range-targets)).
`tools/model_frames.gd -- out=<dir>` (a window) takes pictures of the
leftovers given models after v3.2.0: the duck row turning, a cow tipped,
a shop lamp falling in the saw floor's arena.

- **Quest stations** (after v3.0.0): each station is ONE model,
  `quest_<name>`, holding both looks as mesh nodes `look_off` (to do: lamp
  lit, lever up) and `look_on` (done: lamp dark, green pilot, lever thrown
  and tagged), baked side by side into one texture and shrunk by
  quest_props.py's SCALE as their pictures were. Both pictures
  (`town_quest_<name>_off`, `_on`) stand for it (`PropModels.name_of`,
  `look_of`); PropView shows the look the picture names.
- **Faithful bakes**: the stations and the props drawn flat before (FLAT:
  laundry, the powder shelf, hubcap board, gator hide, probe rack, range
  scoreboard, line sign, the shop lamp) bake their materials' shine too and keep each
  part's own object coordinates for its patterns (attribute `part_co`), so
  hazard stripes, planks and grime fall as in the sprite render; at 160
  texels a unit (512 px for most). The props modelled before kept their
  v3.0.0 bake (64 a unit, no shine, the joined mesh's coordinates).
- `tools/art/prop_sheet.gd -- names=a,b out=<png> [ppu=96]` (a window) lays
  each model's old picture beside the model from the front, the picture's
  three-quarter view, the side, the back and the back three-quarters; a
  station gets a row per look. The sheets are in
  `docs/godot3d/remaster2/props/` with in-game before/after pictures.

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
     texels. Every boss has it now: the baron and Jerry (v3.1.0), and since
     the polish after v3.2.0 the sheriff (`boss`, 52% of the texture
     used), Rudy (50%), the foreman (50%), the derby champ (53%), the Swamp
     King (60%), Maw (55%) and her bare model, and the cow (58%). The
     regular hands kept their v3.0.0 unwrap until polish pass 9, when every
     one was baked again (and the cow, with the head favour below): they had
     41 to 73 texels a metre where the content pass 8 hands had 110 to 125
     (`tools/actor_check.gd -- report`), their arms, bellies and shields big
     blocky texels up close; packed, about twice the texels across. Since
     pass 9 every kind's head gets `HEAD` (1.4) times its share across
     (`_favour_head`; a kind's look may set its own `uv_head`, Mundell 1.6),
     as the face is what reads at the view's size. Jerry, Rudy and the
     foreman (74, 86, 73 a metre at 512) were not baked again: a bake of
     theirs at 1024 took over an hour and lost the graphics card's context
     with other bakes running. A re-bake keeps the gear bones
     (they come from the builds' `gear()` tags) and every frame; fit.json's
     `light` was measured again for each (model against cel, the close-up
     body's mean on the dusk tour).
   - Looks are 512² (`TEXTURE`); `FINE` kinds bake 1024² (the baron, the
     derby champ, the Swamp King, Maw and her bare model: the most parts or
     the biggest bodies; the sheriff, Rudy and the foreman stay 512), with
     fewer samples a texel.
   - A boss's gear (`enemy_actors.py gear("hat")` before its parts,
     `gear("")` after; the cels ignore it) gets bones of its own, never
     merged with the body's, listed in `actors.json` "gear" (bone -> name):
     the sheriff's hat and tin star, Jerry's helmet, Rudy's horns and top hat,
     the foreman's hard hat, the Baron's top hat and monocle, the Swamp King's
     crown and bow shield, Boggs's hood, trunk lid and ram, Maw's curlers and
     glasses (her bare model's girdle plates too, which the 3D view does not
     draw). `features/boss_gear.gd` shoots them off; `tools/gear_fit.gd`
     prints where each sits for bosses.cfg. Added with a `rig-only` run.
   - A kind with its own frame list that walks (the Swamp King, Maw's bare
     model) gets the walk's closing `w4` key too (`_frames`); without it
     ActorView could not run the walk between beats and it snapped.
   - Mundell has a `sit` frame (`skeleton()` in enemy_actors.py: the hips
     down to the knees' height, the boots out front), for a partner on the
     riding mower (vehicles.cfg `pose`).
   - BLUE the hound (`actors_hound.py`, rebuilt in pass 10: the content
     pass 8 dog read as a stiff blue-white dalmatian with black lumps for a
     head and saddle) is a kind with its own frames like the cow, built
     square for the model (`FOR_MODEL`): a lean, deep-chested, muscled
     bluetick. His trunk is two smooth hides lofted through the body's
     sections (`_hd_loft`, front and back, so the spine bends between
     them); the legs are pieces of fixed length posed by two-bone IK, each
     piece as wide where it starts as the last ends and the joints capped
     flush (no ball knobs), long slim muscles, the hind foot set behind the
     hip with a bent stifle and an angled hock, a cat foot oriented with
     him; the ears hang folded close down the cheeks, their front edges
     rolled in; every
     frame builds the same parts in the same order, so nothing pops in or
     out between keys (one tongue that moves, lids that swing). His coat is
     painted, not modelled: every part stores where it sits in its own
     frame (`coat_co`: the body's parts in the body's, the head's in the
     head's, a leg piece by its height on the standing leg), and one shader
     a zone (`_hd_coat`: body, head, leg, tail, ear) paints the bluetick on
     it: pale hair thick with slate roan and ticks, a ragged black saddle,
     the hood down the neck, black patches and spots, tan points on the
     brows, cheeks, muzzle, chest, under the tail and the legs, the ears
     black leather. His model keys more frames than his cels (`HOUND`
     "model_frames", which export_actors.py `_frames` reads): fourteen
     motions of five keys (idle wag, walk, trot, gallop, limp, tracking,
     scratch, shake, going down, down on his side, being got up, getting
     up, the lunge and bite, the hold's head shake) and ten poses; his old
     cel names stay for the pictures (`_CEL_POSE`). export_actors.py labels
     his head's parts `head` (`_label`: within `head_box` of the head's
     middle, `LAST_J`'s `dog_head`), so his face gets more of the texture.
     `hound_face` is his HUD badge's head, three-quarters so the long muzzle
     and the ears read at 28 pixels, cels only (`cels_only`: export_actors.py
     makes no model of it), lit with the rims down and no road dirt
     (`_HD_CLEAN`). `build_enemy_actors.gd -- kinds=hound,hound_face`, then
     the steps below for `hound`. `tools/art/actor_sheet.gd -- kind=hound
     out=<png> [frames=a,b]` (a window) lays out the model in the game's own
     actor shader from five sides and at game size, a row a frame (the
     before and after sheets of pass 10 came from it).
   - The county events' razorback (`actors_hog.py`, content pass 8) is a
     kind with its own frames like the hound (`0`, the gallop `r0..r4`,
     `down`), built square for the model, legs of fixed pieces posed by IK,
     a bristle coat sized to each part (`_hog_coat`: streaks along the body,
     grizzled tips, mud caked up from the ground), a ridge of bristles down
     the spine, the flat snout and tusks; its balls are 16 x 10 (`_hog_sphere`) and its
     looks bake at 256 (`FINE`): it is in the browser's first download. Every name in it starts `_hog`
     (actors_hound.py is exec'd after it and has its own `_leg`, `_body`).
     `build_enemy_actors.gd -- kinds=hog`, then the steps below for `hog`.
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
5. `tools/art/bake_rigs.gd` writes each kind's ragdoll rig beside its model
   (`assets3d/actors/<kind>.rig`, pass 10: the game reads it back instead of
   finding it from the model's vertices at a level's first frame). Run it
   after any change to a model or to its `actors.json` labels or keys;
   `tools/load_speed_check.gd` fails while a rig is out of date.

How ActorView poses and picks a look is in [view3d.md](view3d.md#actors).
Guns in hand stay 2D cels over the 3D view.

`tools/view3d_check.gd` loads every prop and actor scene; run it after either
pipeline.

### Seat views

`scripts/blender/vehicle_cabs.py` models what a driver sees of the airboat,
the stock car and the riding mower from the seat (`cab_airboat`, `cab_car`,
`cab_mower`; [view3d.md](view3d.md#the-seat-view)), with town_props.py's
shapes and materials in the outside models' colours, more detail where the
eye is close (gauges with lit faces and their needles, the car's dice and
window net, the mower's beer) and Mundell's hands (`fist`: four jointed
fingers wrapped round the rim or stick, knuckles, thumb, wrist and cuff,
painted with patches of the photographed hand in `source_art/crowbar_plate.png`,
the hand every gun cel is held in: its skin evened half way to the cels'
mid tone `CEL_SKIN` and its flannel, matt). The cabs bake under their own
light (`CAB_LIGHTS`: the key from ahead, right and above; the town's from
behind the sprite camera lit the backs of the hands and the hood flat). The driver's eye
is the origin (x ahead, y left, z up, map units); a cab is parts: `body`
and moving parts each modelled where it sits and moved so its pivot is the
origin (`pivot`), the pivots and axes in `CAB_PIVOTS` (written as
`cabs.json`). `export_meshes.py` bakes a cab like a station's looks (one glb,
one texture, faithful bake) but leaves it where it was modelled (no drop to
the ground) and packs its many small islands tightly up to `CAB_MOST`
(1024).

```
godot --headless --path godot --script res://tools/art/build_cab_meshes.gd [-- names=cab_car] [no-render]
```

writes `godot/assets3d/cabs/<name>.glb`, `cabs.json` and
`assets/art/mesh_<name>.png` (graded and digitized like the props); then
`pack_assets.gd` and `--import`. Two things that bit: Godot's glTF import
reads a node name ending in `wheel` as a VehicleWheel3D (the car's wheel
part is `steer`), and Blender exits 0 on a Python error unless
`--python-exit-code 1` (the tool passes it). `tools/vehicle_frames.gd` takes
the seat views in a window.

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

`scripts/blender/weapon_views.py` models every gun but the crowbar (the
plates' rigs: the revolver plate, the shotgun plate, the crowbar plate for
throwables), cut by `build_weapon_views.gd`: each render gets its plate's
photographed hand laid over it at the plate's own size and place, so every
gun shows the same hands, light (the three suns) and grade. The .38 and the
sawed-off are modelled in `scripts/blender/weapon_plates.py` (polish pass 9;
before that the game showed the old photographs, hands and all): a
four-inch blued service revolver with walnut stocks and an old side-by-side
coach gun cut down, case-coloured action, rabbit-ear hammers, a split
fore-end in friction tape, the stock sawn to a taped grip. Their reloads
show the gun's works: a view's `states` are renders of their own
(`<name>@<pose>.png`): the cylinder swung out on its crane, the empties
thrown off the ejector, rounds going in; the action broken open, the empties
kicked out, shells going in (one or two). The .38 is turned in the hand toward the
sights (`AIM`) as its photograph pointed, sits a little up the hand
(`SHIFT`) with its cels raised (`PHOTO_NUDGE`) so the fingers round its
walnut grip show as the photograph's did (weapons.cfg's `view_shift` for
it is smaller than the other pistols' for the same reason). Their poses keep the swing the old
photographs had (`PHOTO_POSES`, `held_pose`: turned, grown and moved as the
photograph's barrel was). The crowbar is still its photographed plate. The
5v5 guns' side materials and `pbr(edge=, cavity=)` are in
[modes.md](modes.md#the-guns). `src/melee_blood.gd` wets the crowbar and
sling blade (a cached copy of the graded cel in weapons.gd).

**The junk bench's mods** (content pass 8): `scripts/blender/weapon_mods.py`
runs weapon_views.py's library. Each gun with mods (the .38, the sawed-off,
the rifle, the crossbow, the dynamite) is rendered again with each choice of
its mods on, `<gun>__<shorts>` (rifle__brake_drum), in each of its reload's
states, and cut as its gun is; the .38's and the sawed-off's mods are built
on the barrel (`ON_BARREL`). A mod that lengthens the barrel moves the muzzle
anchor (`FRONTS`: the brake's can, the choke's pipes; `weapon_anchors.json`).
`Armory.art_name` picks the picture; a gun with no picture of its mods falls
back to its own. `tools/bench_frames.gd` (a window) takes every modded gun in
hand, the board, the benches and the scrap.

**Pickups.** `build_item_art.gd` (`item_pictures.py`) also makes the
pickups (and HUD icons) of the crowbar, the .38, the sawed-off and the
dynamite (until polish pass 9 these were the first-person photographs cut
out with the hand on them) and the dynamite sticks' `item_dynamite` (it was a
copy of the shells' box), each about as big as the old picture; the other
first sixteen guns keep the old game's painted pickups.

**Checking them.** `tools/gun_art_check.gd` (check_all, quick): every gun's
every pose, every mod choice's poses, size, hand and muzzle, the muzzle
anchors, the finishers' frames and the boot's cels, the pickups (none with a
hand on it), the switch. `tools/gun_view_frames.gd -- out=<dir>` (a window)
takes every gun in first person at rest, through a shot, through a reload,
going down and coming up in a switch, with each choice of its mods.

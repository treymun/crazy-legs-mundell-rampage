# Chapter 7, the Mothership: sound and music to make

Nothing here has been generated (no ElevenLabs run from the chapter's
worktree). Every cue below is already called by the game, which plays an
existing stand-in until the new one is in the bank, so the chapter is never
silent where it matters. Names are as the game asks for them; families are
`scripts/audio_spec.py add()` families, styles its STYLE keys.

Style for all of it: Redneck Rampage first. The ship is grimy, patched with
county tin and run by B-movie greys; Maw Glorb is a towering alien grandma in
a housecoat and curlers. Rubbery, comic, lowbrow, never sleek sci-fi.

## Effects

| Cue | Family | Style | Prompt | Gen / keep (s) | Stand-in now |
| --- | --- | --- | --- | --- | --- |
| `drone_zap` | attack | alien | A cattle prod jabbed into somebody: a crackling electric zap and a short buzz. | .7 / .45 | the drone's lunge cue (`crawler_click`) |
| `guard_zapper` | attack | alien | A giant bug zapper fired like a gun: three quick crackling purple bolts, fat and buzzy. | .8 / .5 | `barker_blast` |
| `probe_tug` | attack | alien | A tractor beam yanks something: rising wobbling hum snapping into a zap. | .9 / .6 | `saucer_shot` |
| `tailgate_clang` | impact | impact | A bullet ricochets off a rusty pickup truck tailgate: hard tinny clang and a whine. | .6 / .35 | `ricochet` |
| `maw_pin_raise` | warn | creature | A giant raises a huge wooden rolling pin: creaking wood, a deep grunting inhale. | 1.1 / .9 | `foreman_warn` |
| `maw_pin_slam` | boom | boom | A gigantic rolling pin slammed onto a steel deck: booming wooden thud, ringing metal, rattling floor plates. | 1.4 / 1.0 | `explosion` |
| `maw_dryer_whine` | warn | alien | A salon hair dryer the size of a car spinning up: rising whining fan and electric crackle. | 1.0 / .85 | `sheriff_siren` |
| `maw_dryer_blast` | attack | alien | The giant hair dryer fires a fan of heat bolts: roaring hot whoosh with fizzing zaps. | 1.0 / .7 | `sheriff_shot` |
| `maw_stomp_warn` | warn | creature | A huge creature lifts one foot in a fuzzy slipper: a creak of the deck and a building rumble. | 1.1 / 1.0 | `baron_warn` |
| `maw_stomp` | boom | boom | A towering giant stomps a metal deck: deep booming quake, rattling bolts, a shockwave rolling out. | 1.6 / 1.2 | `distant_quarry_blast` |
| `maw_holler` | alert | alien | An enormous alien grandmother hollers to call her children in for supper, warbling and rubbery. | 1.4 / 1.2 | `sheriff_spot` |
| `pod_open` | scene | alien | A crew pod's hatch hisses open: pressure hiss, wet suction pop, a chirp. | .9 / .7 | `secret_slide` |
| `maw_rage` | alert | alien | A giant alien grandma shrieks in fury as her housecoat catches fire: warbling scream and crackling flames. | 1.8 / 1.6 | `sheriff_rage` |
| `maw_bare` | alert | alien | A huge alien bellows with power cells humming up to full charge: furious roar over a rising electric whine. | 1.8 / 1.6 | `baron_rage` |
| `maw_death` | death | alien | A towering alien grandmother's long dying wail, curlers clattering, ending in a crash and fizzling sparks. | 2.6 / 2.4 | `sheriff_death` |
| `maw_pain` | death | alien | A giant alien grandma is hit: short indignant rubbery yelp. | .7 / .5 | (voice `grey`) |
| `maw_down` | death | alien | A giant alien grandma falls: long warbling shriek and a floor-shaking thud. | 1.8 / 1.5 | (voice `grey`) |
| `maw_spot` | alert | alien | A huge alien grandma spots someone: a low suspicious "hmmmm" through a rubbery throat. | .9 / .7 | `sheriff_spot` |
| `drone_buzz` | warn | alien | A cattle prod charging: quick rising electric buzz. | .6 / .4 | `guard_charge` |
| `guard_wind` | warn | alien | A huge bug zapper powering up: rising electric hum with crackling sparks. | .8 / .6 | `barker_wind` |
| `probe_whine` | warn | alien | A small flying eyeball drone focuses its beam: rising wobbling theremin whine. | .8 / .7 | `saucer_charge` |
| `probe_spot` | alert | alien | A floating eyeball robot notices someone: quick curious beeping chirp. | .6 / .4 | `saucer_spot` |
| `beam_hum` | scene | alien | A tractor beam touching someone: thick wobbling hum and a buzzing burn. | .9 / .7 | `arm_ready` |
| `ship_quake` | distant | far | A spaceship coming apart far off: groaning metal, a muffled explosion, rattling debris. | 2.5 / 2.2 | `distant_quarry_blast` |
| `amb_mothership` | ambience | amb | Inside a junky alien mothership: low engine drone, ticking hull, bubbling tanks, a faint distant moo. | 12 / 12.0 | none (the ambience is silent till made) |

## Stings

| Cue | Family | Prompt | Gen / keep (s) | Stand-in now |
| --- | --- | --- | --- | --- |
| `maw_intro` | sting | A menacing cowpunk riff with a theremin wail and a slammed screen door: final boss arrival sting. | 2.5 / 2.2 | `shakedown_intro` |
| `maw_end` | sting | A huge triumphant cowpunk final chord with a falling theremin and a cymbal crash: the last boss is down. | 3.0 / 2.6 | `shakedown_end` |

## Voices (captions already in the level)

| Cue | Text | Voice, fx |
| --- | --- | --- |
| `talk_ship-pa_0` | Hooman loose on deck four. | an alien PA voice, "pa" |
| `talk_ship-pa_1` | Which one is the hooman? | local (a grey crewman) |
| `talk_mess-pa_0` | Corn dogs are off. | alien PA, "pa" |
| `talk_mess-pa_1` | Again? | local |
| `talk_engine-pa_0` | Who put diesel in the drive? | alien PA, "pa" |
| `talk_engine-pa_1` | Sign said unleaded. | local |
| `talk_bridge-pa_0` | Where's my boy's tin star? | Maw (a big rubbery alien grandma), "pa" |
| `talk_bridge-pa_1` | Hickston, Maw. | local |
| `county_dispatch_5` | Nothing up there but stars. | dispatch, "radio" |

## Music (files for `godot/assets/music`, in the chapter's `music_mothership` file)

In the style of the chapter tracks above them in `scripts/audio_spec.py`
(MUSIC, FIGHTS): the same BAND and FIGHT_TAIL, with a theremin or musical saw
for the alien in it.

- Level track `mothership_score`, "Abducted Hoedown", 136 BPM: Dark, spooky
  cowpunk with a B-movie flying-saucer theremin answering a twangy tremolo
  guitar hook, slap bass walking like a creeping alien, a clanking hull-plate
  backbeat; a half-time middle with a musical saw, then the hook returns bigger.
- Fight track `fight_mothership`, "Ray Gun Barn Dance", 176 BPM: Frantic
  hillbilly punk at 176 BPM: furious banjo rolls and sawing fiddle against a
  wailing theremin riff, overdriven twang guitar, washboard and crashing
  train-beat drums. Manic, like a hoedown in a crashing spaceship. (FIGHT_TAIL
  for the loop.)
- Final boss track `boss_mothership`, "Maw's Last Supper", 148 BPM: The
  biggest, heaviest cut on the record: thundering country-metal riff with
  detuned guitars, booming toms and anvil hits, a church-organ swell and a
  screaming theremin lead, gang-chant stabs; relentless, seamless loop, no
  intro or ending (FIGHT_TAIL rules), played from the moment the core's iris
  opens till Maw falls.

## After generating: the wiring to switch on

- `godot/src/assets.gd PENDING_MUSIC`: take off each track once its `.ogg`
  is in `godot/assets/music` (and add its cut-off to `playback_ends.json` as
  the others have); verify_assets then checks it like the rest.
- The effects in the first table up to `ship_quake` and the stings are picked
  up by name the moment they are in the bank (`ShipAliens.cue()`); nothing to
  change.
- `godot/data/tuning/enemies.cfg`: `[drone] windup` to `drone_buzz`,
  `[tin_guard] windup` to `guard_wind`, `[probe] windup` to `probe_whine` and
  `alert` to `probe_spot`, `[maw] alert` to `maw_spot` and `voice` to `maw`
  (which plays `maw_pain` / `maw_down`).
- `amb_mothership` plays from the level's ambience as soon as it exists.

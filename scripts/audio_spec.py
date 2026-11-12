"""What every active audio cue should be: the production plan for the game's sound.

One entry per cue the runtime can play (traced from godot/src; see
audio_src/manifest.json for the triggers). An entry is one of:

  G(prompt, gen, keep)   a recording generated from `prompt`, `gen` seconds
                         asked for, trimmed to `keep` seconds (None = the
                         length the cue had, which gameplay timing was tuned to)
  D(base, how, ...)      derived locally from another cue's source recording:
                         "room"  the indoor tail layered under `base`
                         "event" another hit taken from the same recording
                         "pitch" the same hit retuned
  V(text, voice, fx)     a spoken line; `text` is the caption (`say`: what was sent
                         instead, `heard`: how its transcript spells the words)

FAMILY sets the finishing chain (tone curve, level, fades) each cue gets in
scripts/audio_build.py. Nothing here costs money: scripts/audio_produce.py
turns the G and V entries into paid requests through the budget ledger.
"""
from __future__ import annotations

STYLE = {
    # appended to every prompt of the family
    "gun": "Close-miked, punchy, dry, hard transient, 1990s PC shooter sound effect. One single shot, no echo tail, no music.",
    "mech": "Close, dry, crisp foley recording of real hardware. One clean sound, no music, no voice.",
    "impact": "Close, dry, punchy foley. One single impact, no music.",
    "boom": "Punchy, chunky, slightly crunchy 1990s game explosion with weight and a short tail. No music.",
    "creature": "Cartoonish, expressive, dry, close. One single sound, no music.",
    "alien": "Wet, rubbery, slightly comic B-movie alien sound, dry and close. No music.",
    "tool": "Gritty industrial machine sound, close and dry. No music, no voice.",
    "foot": "Close foley, dry, no ambience, no music.",
    "amb": "Soft, mellow, low-key background ambience bed, full-bodied rather than shrill, no sudden events, seamless loop, no music, no voices.",
    "far": "Heard from a distance across open country, soft, slightly muffled, no music.",
    "ui": "Tiny, dry, clean, tactile 1990s PC game interface sound. No music, no voice.",
    "vox": "One man, a gravel-voiced comic hillbilly, dry and close. No music, no other sounds.",
    "sting": "Gritty cowpunk rockabilly bar band: twangy overdriven electric guitar, slap bass, live drums. Instrumental, short, no vocals.",
    "scene": "Close, dry, comic prop destruction foley. No music, no voice.",
    "crowd": "A small rural outdoor crowd, a few dozen people, short, slightly distant. No music.",
}


def G(prompt, gen=1.0, keep=None, style="mech", **opts):
    return {"make": "gen", "prompt": prompt, "gen": gen, "keep": keep, "style": style, **opts}


def D(base, how="room", **opts):
    return {"make": "derive", "base": base, "how": how, **opts}


def V(text, voice="mundell", fx="", **opts):
    return {"make": "voice", "text": text, "voice": voice, "fx": fx, **opts}


def LOOP(prompt, gen, keep=None, style="amb", **opts):
    return {"make": "gen", "prompt": prompt, "gen": gen, "keep": keep, "style": style,
            "loop": True, **opts}


CUES: dict[str, dict] = {}
FAMILY: dict[str, str] = {}


def add(family: str, **cues) -> None:
    for name, entry in cues.items():
        name = name.replace("__", "-")
        assert name not in CUES, name
        CUES[name] = entry
        FAMILY[name] = family


# ------------------------------------------------------------ weapon reports
add("report",
    revolver=G("A .38 Special snub-nose revolver gunshot: sharp crack with a meaty low thump.", 1.0, .46, "gun"),
    revolver_alt=G("A sharp, concussive .38 Special revolver gunshot: loud metallic bark, high-pressure muzzle crack with a solid low thump and tight slapback echo.", 1.0, .5, "gun"),
    shotgun=G("A single 12 gauge shotgun gunshot, close microphone, outdoors, very loud and heavy with a deep boom and a sharp crack, dry, no echo.", 1.4, .95, "gun", level=-1.5, punch=dict(thump=(120, 46, .13), body=.11, crack=.9, tail=.34)),
    shotgun_both=G("Two 12 gauge shotgun barrels fired at the same instant, close microphone, enormous deep boom and tearing crack, then two empty shells clattering on gravel.", 2.4, 1.7, "gun", level=-1.0, punch=dict(thump=(110, 38, .2), body=.15, crack=1.0, tail=.6, double=.022)),
    rifle=G("A single AK-47 assault rifle gunshot, close microphone, outdoors, loud punchy crack with a heavy thud and metallic action, dry, no echo.", 1.0, .36, "gun", level=-4.0, punch=dict(thump=(150, 70, .055), body=.045, crack=.9, tail=.09, clack=.3)),
    rifle_alt=G("One AK-47 rifle gunshot, close and loud, deep punchy bark with a hard crack and a short metallic rattle, dry.", 1.0, .36, "gun", level=-4.0, punch=dict(thump=(142, 66, .06), body=.05, crack=.8, tail=.1, clack=.26, seed=11)),
    rifle_alt2=G("A single Kalashnikov rifle shot fired outdoors, close microphone, aggressive heavy crack and thump with bolt clatter, dry.", 1.0, .36, "gun", level=-4.0, punch=dict(thump=(158, 74, .05), body=.042, crack=1.0, tail=.085, clack=.34, seed=19)),
    armgun=G("A bio-mechanical alien weapon fires: deep organic carapace thrum, high-voltage plasma discharge crackle and a sizzling energy burst.", 1.1, .55, "alien"),
    bottle_launcher=G("A bottle rocket fired from a metal pipe: violent gunpowder fizzle and a heavy hollow thoonk, then a loud whistling whoosh screaming away.", 1.2, .6, "gun"),
    bowling_ball=G("A heavy bowling ball heaved and rolling away on hard ground: grunt-free thud then a rumbling roll.", 1.5, .95, "impact"),
    cow_launcher=G("A homemade stovepipe cannon fires a cow: deep hollow black-powder whoomp inside a wide steel pipe, a metallic ring, then a startled moo flying away fast.", 1.5, .95, "impact"),
    crossbow=G("A heavy wooden crossbow fires under high tension: violent cable snap twang, solid wooden clack and a whooshing bolt.", 1.0, .5, "mech"),
    powder_keg=G("A wooden powder keg lobbed underhand: heavy wooden heave, rope creak and a sloshing thump.", 1.2, .72, "impact"),
    pressure_gun=G("A steam-powered copper pressure gun discharges: violent steam valve hiss over a heavy clanking copper piston thump with metallic echo.", 1.1, .6, "tool"),
    ripsaw=G("A circular saw blade launched from a two-stroke saw gun: engine bark, aggressive metal blade launch with a resonant buzz spinning away.", 1.1, .5, "tool"),
    riveter=G("A heavy pneumatic industrial rivet gun fires one steel stud: high-pressure air burst and an authoritative heavy metallic slam.", .9, .36, "tool"),
    riveter_pair=G("A heavy pneumatic industrial rivet gun fires two steel studs fast: two air bursts and two heavy metallic slams.", 1.0, .44, "tool"),
    teat_gun=G("A short squirt of milk fired under pressure: quick wet spurt with a tiny rubbery pop.", .6, .22, "creature"),
    tnt_throw=G("A man throws a stick of dynamite: quick cloth whoosh and effortful swing.", .8, .34, "impact"),
    match_strike=G("A wooden match struck on a rough box and flaring alight.", 1.0, .46, "mech"),
    )
add("loop_tool",
    fuse_hiss=LOOP("A dynamite fuse burning: steady sputtering spark hiss.", 2.0, 1.4, "mech"),
    saw_motor=LOOP("A small two-stroke saw motor grinding metal at steady revs, harsh buzzing whine.", 2.0, 1.4, "tool"),
    )
add("room",
    **{f"room_{base}": D(base) for base in (
        "revolver", "shotgun", "shotgun_both", "rifle", "riveter", "riveter_pair",
        "pressure_gun", "bottle_launcher", "cow_launcher", "teat_gun",
        "explosion", "arm_impact", "rocket_pop", "foreman_cut", "rudy_horn",
        "boiler_release", "chain_crack", "deputy_shot", "tosser_throw", "bowling_hit",
        "saw_hit", "tnt_bounce", "door", "gate", "secret_slide", "can_kick",
        "glass_break", "sink_flush", "toilet_burst", "tv_pop", "vending_clunk",
        "window_smash")})

# ------------------------------------------------------------------ dry fire
add("dry",
    dry_revolver=G("A revolver hammer falls on an empty chamber: one small metallic click.", .5, None),
    dry_shotgun=G("A shotgun's twin hammers fall on empty barrels: dull double metal click.", .5, None),
    dry_rifle=G("A rifle trigger pulled on an empty chamber: thin springy click.", .5, None),
    dry_crossbow=G("An unloaded crossbow trigger clacks: dry wooden click.", .5, None),
    dry_ripsaw=G("An empty saw launcher's catch snaps shut: tinny metal clack.", .5, None),
    dry_armgun=G("An exhausted alien bio-gun: one small wet deflating blip.", .5, None, "alien"),
    dry_tnt=G("A hand pats an empty canvas pouch: soft dull pat.", .5, None, "foot"),
    dry_bottle_launcher=G("An empty steel pipe launcher tapped: hollow metallic tonk.", .5, None),
    dry_riveter=G("An empty pneumatic rivet gun: weak puff of air and a click.", .5, None, "tool"),
    dry_pressure_gun=G("A steam gun with no pressure: feeble wheeze and a valve tick.", .5, None, "tool"),
    dry_bowling_ball=D("dry_tnt", "pitch", cents=-300),
    dry_powder_keg=D("dry_tnt", "pitch", cents=-500),
    dry_cow_launcher=D("dry_bottle_launcher", "pitch", cents=-400),
    dry_teat_gun=G("An empty rubber squeeze bulb: tiny dry air squeak.", .5, None, "creature"),
    )

# --------------------------------------------------------------------- equip
add("equip",
    equip_crowbar=G("A steel crowbar picked up and gripped: short metal scrape and clink.", .6, None),
    equip_revolver=G("A revolver drawn from a leather holster and cocked: leather slide and click.", .6, None),
    equip_shotgun=G("A double-barrel shotgun snapped shut and shouldered: chunky wood-and-steel clack.", .6, None),
    equip_crossbow=G("A wooden crossbow raised: wood creak and string tick.", .6, None),
    equip_rifle=G("A ranch rifle raised and its bolt racked quickly.", .6, None),
    equip_ripsaw=G("A saw-blade launcher hefted: blade rattle and metal clunk.", .6, None, "tool"),
    equip_armgun=G("A slimy alien arm cannon slipped on: wet squelch and soft organic gurgle.", .6, None, "alien"),
    equip_tnt=G("Sticks of dynamite pulled from a canvas bag: paper rustle and wooden knock.", .6, None, "foot"),
    equip_slingblade=G("A long curved steel blade drawn: ringing metallic shing.", .6, None),
    equip_bottle_launcher=G("A steel pipe launcher lifted with glass bottles clinking.", .6, None),
    equip_riveter=G("A pneumatic rivet gun picked up: air hose hiss and metal clank.", .6, None, "tool"),
    equip_pressure_gun=G("A copper steam gun lifted: gauge tick and short steam hiss.", .6, None, "tool"),
    equip_bowling_ball=G("A bowling ball picked up: heavy hollow knock and hand slap.", .6, None, "impact"),
    equip_powder_keg=G("A small wooden keg hoisted: wood creak and powder slosh.", .6, None, "impact"),
    equip_cow_launcher=G("A big farm catapult cranked ready: ratchet clicks and a low short moo.", .6, None, "creature"),
    equip_teat_gun=G("A milk canister sloshes and a rubber hose squeaks.", .6, None, "creature"),
    )

# -------------------------------------------------------------------- reload
add("reload",
    rev_cylinder=G("A revolver cylinder swung out and spun: ratcheting clicks.", .6, None),
    rev_extract=G("Empty brass revolver cartridges dumped out, tinkling.", .6, None),
    rev_lock=G("A revolver cylinder snapped shut: one firm click.", .5, None),
    shot_hinge=G("A break-action shotgun cracked open on its hinge: heavy clack.", .6, None),
    shot_extract=G("Two spent shotgun shells pulled and dropped: plastic-and-brass clatter.", .6, None),
    shot_shell=G("A shotgun shell pushed into a barrel: hollow thup.", .5, None),
    shot_lock=G("A break-action shotgun snapped shut: solid clunk.", .5, None),
    reload=G("A rifle magazine release pressed: sharp metal click.", .5, None),
    mag_out=G("A rifle magazine pulled out: metal slide and click.", .5, None),
    mag_in=G("A rifle magazine slapped in: firm metallic clack.", .5, None),
    bolt_rack=G("A rifle bolt racked back and forward: fast double clack.", .5, None),
    bow_hook=G("A crossbow string hooked by a cocking lever: small metal tick.", .5, None),
    bow_pull=G("A crossbow string drawn back: tense creaking stretch.", .5, None),
    bow_seat=G("A bolt laid into a crossbow groove: wooden tap.", .5, None),
    bow_latch=G("A crossbow latch clicks locked.", .5, None),
    saw_latch=G("A spring latch on a saw launcher flicked: thin metal snap.", .5, None, "tool"),
    saw_seat=G("A circular saw blade dropped onto a spindle: ringing metal clink.", .5, None, "tool"),
    arm_vent=G("An alien bio-gun vents: wet hiss of gas.", .5, None, "alien"),
    arm_cell=G("A slimy pod pushed into an alien gun: squelching plop.", .5, None, "alien"),
    arm_ready=G("An alien gun primed: short rising organic chirp.", .5, None, "alien"),
    rocket_breech=G("A steel launcher breech swung open: hollow pipe clank.", .5, None),
    rocket_case=G("A spent bottle pulled from a steel tube: glass scrape and clink.", .5, None),
    rocket_seat=G("A bottle rocket slid into a steel tube: glassy slide and thunk.", .5, None),
    rocket_lock=G("A steel launcher breech slammed shut: ringing clang.", .5, None),
    rivet_mag=G("A strip magazine released from a rivet gun: metal clack.", .5, None, "tool"),
    rivet_strip=G("A strip of rivets fed into a rivet gun: quick ratcheting.", .5, None, "tool"),
    rivet_lock=G("A rivet gun cover snapped shut with an air chuff.", .5, None, "tool"),
    pressure_seal=G("A brass pressure valve unscrewed: squeaky twist.", .5, None, "tool"),
    pressure_vent=G("Steam vented from a ruptured copper pipe: hard loud hiss.", 1.2, None, "tool"),
    pressure_charge=G("A steam cartridge seated in copper: metallic clunk and rising hiss.", .5, None, "tool"),
    pressure_pump=G("A hand pump pressurising a copper tank: two quick strokes.", .6, None, "tool"),
    eject=G("A heavy latch thrown open: one blunt metal clack.", .5, None),
    load=G("A heavy object dropped into a wooden cradle: hollow thud.", .5, None, "impact"),
    close=G("A heavy wooden lid shut and latched: thunk and click.", .5, None),
    gulp=G("A man takes one big noisy gulp of beer.", .9, None, "vox"),
    )

# -------------------------------------------------------- melee and impacts
add("melee",
    crowbar=G("A steel crowbar swung hard through the air: fast heavy whoosh.", .6, None, "impact"),
    crowbar_hit=G("A steel crowbar smashes into a body: heavy meaty thwack with a bone crack and a low metal ring.", .7, None, "impact"),
    slingblade=G("A long blade swung in a wide arc: slicing whoosh with a metal sing.", .6, None, "impact"),
    sling_hit=G("A big blade chops deep into flesh: loud wet chopping thunk with a heavy thud.", 1.0, None, "impact"),
    )
add("impact",
    impact_dirt=G("A bullet hits dry dirt: soft thud and spray of grit.", .5, None, "impact"),
    impact_plaster=G("A bullet hits a plaster wall: chalky crack and crumble.", .5, None, "impact"),
    impact_wood=G("A bullet hits a wooden plank: sharp splintering thock.", .5, None, "impact"),
    impact_rivet=G("A steel rivet punches into a wall: hard metallic spang.", .5, None, "impact"),
    impact_pressure=G("A blast of steam hits a wall: sharp hissing splat.", .6, None, "tool"),
    ricochet=G("A bullet ricochets off steel: classic western whining ping.", .7, .3, "impact"),
    pressure_interrupt=G("A burst of steam knocks a man back: hiss and a startled grunt.", .6, None, "tool"),
    saw_hit=G("A saw blade slicing through wet bone and flesh: violent buzzing rip, squelch and splatter.", .7, None, "tool"),
    gib_burst=G("A wet, gruesome, over-the-top fleshy explosion of meat and snapping bone with a squelching blood burst, 1990s PC shooter sound effect.", 1.2, .9, "impact"),
    gib_splat=G("A wet chunk of meat slaps onto hard concrete and slides: short wet squelch.", .6, .4, "impact"),
    saw_bounce=G("A saw blade glances off stone: bright ringing clang.", .5, None, "tool"),
    bowling_hit=G("A bowling ball slams into a body: heavy bone-cracking wallop.", .9, None, "impact"),
    tnt_bounce=G("A stick of dynamite bounces on hard ground: light wooden knock.", .5, None, "impact"),
    football_bounce=G("A leather football bounces on turf: hollow thump.", .5, None, "impact"),
    chalk_pop=G("A ball of chalk dust bursts: soft powdery puff.", .5, None, "impact"),
    tosser_glass=G("A glass bottle shatters on the ground.", .6, None, "scene"),
    rocket_whistle=G("A bottle rocket screams past: rising shrill whistle.", .6, None, "gun"),
    )
add("boom",
    explosion=G("A dynamite explosion: massive concussive boom with flying dirt and debris.", 2.0, 1.4, "boom"),
    rocket_pop=G("A bottle rocket bursts: sharp crackling firework pop.", .8, .42, "boom"),
    arm_impact=G("An alien plasma glob detonates: wet sizzling splat with an electric crackle.", .9, .55, "alien"),
    cow_moo=G("A cow gives one long, indignant, comical moo.", 1.3, 1.0, "creature"),
    )

# ------------------------------------------------------------------ enemies
add("alert",
    alien_alert=G("An alien guard notices something: short guttural chittering snarl.", .7, None, "alien"),
    billy_alert=G("A big dumb hillbilly grunts 'huh?' in surprise.", .7, None, "vox"),
    clone_alert=G("A reedy hillbilly clone yelps a nasal 'hey!'.", .7, None, "vox"),
    coot_alert=G("A cranky old man snorts a short wheezy 'eh?'.", .6, None, "vox"),
    saucer_spot=G("A tiny flying saucer locks on: quick rising electronic chirp.", .6, None, "alien"),
    sheriff_spot=G("A huge alien sheriff growls low and menacing, short.", .7, None, "alien"),
    skeeter=G("A giant mosquito buzzes angrily close by, very short.", .5, None, "creature"),
    )
add("warn",
    chain_raise=G("A heavy logging chain hauled up and swung overhead: rattling links building.", 1.0, None, "tool"),
    deputy_work=G("A pump shotgun racked slowly and deliberately.", .7, None),
    rat_hiss=G("A big rat hisses viciously, rising.", .9, None, "creature"),
    tosser_rattle=G("Glass bottles rattling together in a crate, getting louder.", .8, None, "scene"),
    barker_wind=G("A carnival barker's megaphone squeals with rising feedback.", .9, None, "tool"),
    baron_warn=G("A huge copper boiler builds pressure: rising groaning metal and whistle.", 1.2, None, "tool"),
    boiler_priming=G("A steam boiler primes: rising gurgle and hiss.", 1.0, None, "tool"),
    chalk_cough=G("A creature hacks up a dry dusty cough before spitting.", .7, None, "creature"),
    clone_bolt=G("A rifle bolt worked fast: one quick clack.", .5, None),
    coot_cock=G("An old pistol hammer cocked: one click.", .5, None),
    crawler_click=G("An alien crawler's mandibles clicking rapidly.", .9, None, "alien"),
    enemy_pump=G("A pump-action shotgun racked fast: chk-chk.", .5, None),
    foreman_warn=G("A giant sawmill blade spins up: rising metallic whine.", 1.1, None, "tool"),
    guard_charge=G("An alien plasma weapon charging: quick rising electric hum.", .6, None, "alien"),
    lantern_charge=G("A gas lantern flares up with a rising roar.", .9, None, "tool"),
    millhand_rev=G("A chainsaw revved up hard, once.", .9, None, "tool"),
    rudy_warn=G("A clown's bulb horn squeezed slowly, wheezing in before the honk.", 1.1, None, "creature"),
    saucer_charge=G("A small UFO weapon winds up: rising wobbling theremin tone.", .8, None, "alien"),
    sheriff_siren=G("One rising whoop of an old police siren.", .7, None, "tool"),
    skeeter_dive=G("A giant mosquito dives: rising nasal whine.", .6, None, "creature"),
    whistle=G("A referee's whistle blown hard, one sharp blast.", .7, None, "creature"),
    )
add("attack",
    barker_blast=G("A megaphone blares a distorted honking blast.", .9, None, "tool"),
    boiler_release=G("A boiler releases a violent jet of steam.", .8, None, "tool"),
    chain_crack=G("A heavy chain whipped and cracking against the ground.", .7, None, "tool"),
    chalk_spit=G("A creature spits a thick gob: quick wet ptooey.", .5, None, "creature"),
    deputy_shot=G("A police pump shotgun fires: hard flat blast.", .7, .36, "gun"),
    enemy=G("A cheap bolt-action rifle fired by an enemy: thin cracking shot.", .6, .28, "gun"),
    enemy_pistol=G("An old rusty pistol fired: small popping gunshot.", .6, .28, "gun"),
    enemy_scatter=G("A rusty scattergun fired at mid distance: boxy boom.", .8, .42, "gun"),
    lantern_spit=G("A fireball hurled from a lantern: whooshing flame burst.", .9, None, "tool"),
    millhand_hit=G("A chainsaw bites into a body: brutal short revving rip.", .9, None, "tool"),
    plasma=G("An alien plasma pistol fires: zappy descending laser squelch.", .7, .42, "alien"),
    rat_blow=G("A blowpipe dart fired: sharp breath puff and thwip.", .6, None, "creature"),
    saucer_shot=G("A tiny UFO fires a ray: quick bright sci-fi zap.", .6, .34, "alien"),
    skeeter_bite=G("A giant mosquito stabs and slurps: quick wet jab.", .5, None, "creature"),
    tosser_throw=G("A man hurls a glass bottle: cloth whoosh and bottle whistle.", .5, None, "impact"),
    sheriff_shot=G("A giant alien revolver fires: deep booming plasma shot.", .8, .5, "alien"),
    football_throw=G("A football thrown hard: quick spiralling whoosh.", .6, None, "impact"),
    foreman_cut=G("Circular saw blades launched screaming down a lane.", .8, .5, "tool"),
    rudy_horn=G("A clown's bulb horn honked five times very fast, loud and rude.", 1.0, .66, "creature"),
    )
add("death",
    actor_cloth_pain=G("A hillbilly grunts in pain: short 'oof'.", .6, None, "vox"),
    actor_cloth_down=G("A hillbilly dies with a comical drawn-out groan and falls.", .9, .62, "vox"),
    actor_shell_pain=G("An alien shrieks in pain: short gurgling squeal.", .6, None, "alien"),
    actor_shell_down=G("An alien dies: wet gurgling screech and splat.", .9, .64, "alien"),
    actor_tool_pain=G("A big man in metal gear is hit: grunt and clank.", .6, None, "vox"),
    actor_tool_down=G("A heavy man in metal gear collapses: groan and clattering crash.", 1.0, .68, "vox"),
    skeeter_pop=G("A giant bug bursts: quick wet pop.", .5, None, "creature"),
    chicken=G("A chicken squawks in alarm, short.", .6, None, "creature"),
    pig=G("A pig squeals, short and indignant.", .6, None, "creature"),
    # Voices by character (enemies.gd VOICES); the material cues above stay as the fallback.
    hick_pain_1=G("A burly backwoods man is hit: sharp startled 'ow!' yelp.", .6, .5, "vox"),
    hick_pain_2=G("A backwoods man takes a hit: gruff winded 'hrrgh' grunt.", .6, .5, "vox"),
    hick_pain_3=G("A backwoods man is stung: angry yowl, short.", .6, .5, "vox"),
    hick_down_1=G("A backwoods man is shot dead: hollering scream that trails off as he falls over.", 1.4, 1.2, "vox"),
    hick_down_2=G("A backwoods man dies: choked gurgling 'aaugh' and a heavy thud of a body on dirt.", 1.4, 1.2, "vox"),
    hick_down_3=G("A backwoods man dies: long wavering comic yell, then a thud.", 1.5, 1.3, "vox"),
    coot_pain=G("A wheezy old man is hit: cracked high 'yeowch'.", .6, .5, "vox"),
    coot_down=G("A wheezy old man dies: thin cracking wail fading out, then a light thud.", 1.4, 1.2, "vox"),
    grey_pain=G("A thin grey alien is hit: short warbling electronic-throated shriek.", .6, .5, "alien"),
    grey_down=G("A thin grey alien dies: descending warbling shriek ending in a wet gurgle.", 1.4, 1.2, "alien"),
    jerry_pain=G("A proud older Texas businessman is hit: indignant grunt 'hngh'.", .6, .5, "vox"),
    jerry_down=G("A proud older Texas businessman dies: long outraged bellow, then a heavy fall.", 1.6, 1.4, "vox"),
    rudy_down=G("A booming carnival barker dies: theatrical drawn-out howl, then a crash.", 1.6, 1.4, "vox"),
    foreman_down=G("A huge gruff sawmill boss dies: deep roar, then a heavy crash of gear and sawblades.", 1.6, 1.4, "vox"),
    baron_down=G("A big man sealed in a copper boiler suit dies: muffled roar inside metal, hiss of steam, clanging collapse.", 1.8, 1.6, "tool"),
    spitter_down=G("A dusty choking creature dies: dry rasping cough and a wet collapse.", 1.2, 1.0, "creature"),
    )

# ------------------------------------------------------------------- player
add("player",
    hurt=G("A man grunts in pain: short gruff 'ugh'.", .6, None, "vox"),
    hurt_alt=G("A man yelps in pain: short 'ow!'.", .6, None, "vox"),
    hurt_alt2=G("A man hisses in pain through his teeth: 'agh'.", .7, None, "vox"),
    player_down=G("A man dies with a long comical groan trailing off.", 1.8, None, "vox"),
    belch=G("A man lets out a long, deep, wet, comical belch.", 1.0, None, "vox"),
    yee_haw=G("A man whoops a loud, gleeful, twangy 'yee-haw!'.", 1.6, None, "vox"),
    yee_haw_alt=G("A man hollers a rowdy rebel yell, 'yeee-hoo!'.", 1.8, None, "vox"),
    county_fall_back=G("A scared man shouts 'fall back!' in a thick country accent.", .9, .6, "vox"),
    )
add("consume",
    crunch=G("A man crunches a mouthful of crispy pork rinds.", .7, None, "vox"),
    moonshine=G("A man swigs from a jug then gasps a fiery 'whoo!'.", 1.1, None, "vox"),
    whiskey_glug=G("Whiskey glugging from a bottle, two gulps.", .8, None, "vox"),
    cowpie_pick=G("A hand squelches into something soft and wet.", .7, None, "creature"),
    )
add("pickup",
    pickup=G("A box of ammunition scooped up: short metallic rattle.", .5, None),
    weapon_pickup=G("A gun grabbed off the ground: quick metal clack.", .5, None),
    key_pickup=G("A brass key picked up: bright jingle.", .5, None),
    )
add("foot",
    step_grass_0=G("Four separate slow boot steps on dry grass.", 3.0, None, "foot", event=0),
    step_grass_1=D("step_grass_0", "event", event=2),
    step_gravel_0=G("Four separate slow boot steps on loose gravel.", 3.0, None, "foot", event=0),
    step_gravel_1=D("step_gravel_0", "event", event=2),
    step_mud_0=G("Four separate slow boot steps in thick sucking mud.", 3.0, None, "foot", event=0),
    step_mud_1=D("step_mud_0", "event", event=2),
    step_tile_0=G("Four separate slow hard boot steps on a tile floor.", 3.0, None, "foot", event=0),
    step_tile_1=D("step_tile_0", "event", event=2),
    step_water_0=G("Four separate slow boot steps splashing through shallow water.", 3.0, None, "foot", event=0),
    step_water_1=D("step_water_0", "event", event=2),
    step_wood_0=G("Four separate slow boot steps on hollow wooden boards.", 3.0, None, "foot", event=0),
    step_wood_1=D("step_wood_0", "event", event=2),
    )

# ---------------------------------------------------------- world and props
add("door",
    door=G("A wooden door yanked open: latch click and creak.", .7, None),
    gate=G("A rusty iron farm gate swings open with a squeal.", .9, None),
    secret_slide=G("A heavy hidden wall panel slides aside: stone-on-wood grinding.", .9, None, "tool"),
    )
add("scene",
    can_kick=G("A tin can shot and sent clattering.", .8, None, "scene"),
    glass_break=G("A window pane shattering.", .9, None, "scene"),
    jukebox_hit=G("A jukebox shot: record scratch, sparks and a dying warble.", 1.5, None, "scene"),
    scenery_belt=G("A leather drive belt snaps and flaps.", .8, None, "tool"),
    scenery_cans=G("A stack of tin cans knocked over, clattering.", .9, None, "scene"),
    scenery_pipe=G("A copper pipe struck: ringing clang with a hiss.", 1.0, None, "tool"),
    scenery_prize=G("A plush carnival prize shot: squeaky toy pop.", .6, None, "creature"),
    scenery_scrap=G("Scrap metal hit and rattling.", .8, None, "scene"),
    sink_flush=G("A tap turned on, water gushing into a steel sink then gurgling away.", 1.6, None, "scene"),
    toilet_burst=G("A porcelain toilet smashed and gushing water.", 1.5, None, "scene"),
    tv_pop=G("A television tube implodes: pop, glass and electric fizz.", .9, None, "scene"),
    vending_clunk=G("A vending machine shot: clunk, coins and a can dropping.", 1.2, None, "scene"),
    window_smash=G("A large window smashed, glass raining down.", .9, None, "scene"),
    )
add("station",
    brake_ratchet=G("A big iron brake lever ratcheted down: heavy clanking clicks.", .9, None, "tool"),
    breaker_thunk=G("A big electrical breaker switch thrown: heavy thunk and hum.", .9, None, "tool"),
    broadcast_cut=G("A PA system cut off: squeal, click, static fading.", .9, None, "tool"),
    fair_bell=G("A carnival high-striker bell struck: bright ding.", 1.2, None, "scene"),
    mill_isolate=G("A large valve wheel cranked shut: squeaking and a clunk.", .9, None, "tool"),
    mill_trip=G("A heavy machine relay trips: clack and a motor winding down.", .9, None, "tool"),
    )

# ----------------------------------------------------------------- ambience
add("ambience",
    amb_yard=LOOP("Rural dusk outdoors: low steady wind in dry grass and trees, gentle soft crickets in the background, faint distant frogs.", 12, 12.0),
    amb_room=LOOP("Quiet wooden room indoors: faint electrical hum, a soft creak, muffled wind outside.", 12, 12.0),
    amb_barn=LOOP("Inside an old barn: wood creaking, wind through gaps, a few flies.", 12, 12.0),
    amb_creek=LOOP("A small creek babbling over stones with crickets.", 12, 12.0),
    amb_fair=LOOP("An empty county fair at night: generator hum, buzzing light bulbs, creaking rides, flapping canvas.", 14, 14.0),
    amb_fair_after=LOOP("A fairground after the power is cut: wind, flapping canvas, a loose chain ticking.", 12, 11.6),
    amb_mill=LOOP("Inside a running sawmill: droning belts and machinery, steady rumble.", 14, 14.0),
    amb_mill_bank=LOOP("A log pond outside a quiet sawmill: lapping water, frogs, light rain on timber.", 14, 14.0),
    amb_quarry=LOOP("An open limestone quarry: wind over rock, distant machinery thud, falling grit.", 12, 12.0),
    amb_quarry_line=LOOP("Inside a bottling works: conveyor rattle, clinking glass, hissing steam.", 12, 12.0),
    amb_quarry_after=LOOP("A shut-down quarry: wind, dripping water, settling metal.", 12, 11.6),
    )
add("distant",
    distant_crow=G("One crow cawing twice far away.", 1.0, None, "far"),
    distant_dog=G("A farm dog barking twice far away.", 1.0, None, "far"),
    distant_fair_generator=G("A diesel generator chugging in the distance.", 2.5, None, "far"),
    distant_fair_motif=G("A broken calliope playing a few wobbly notes far away.", 2.5, None, "far"),
    distant_fair_pa=G("A distorted fairground loudspeaker crackling with garbled speech far away.", 1.5, None, "far"),
    distant_fair_rattle=G("A rickety ride chain rattling in the distance.", .8, None, "far"),
    distant_mill_pump=G("A water pump thumping rhythmically in the distance.", 2.0, None, "far"),
    distant_mill_timber=G("A big log rolling and crashing onto a pile far away.", 2.0, None, "far"),
    distant_quarry_bottler=G("Glass bottles clinking along a machine far away.", 1.3, None, "far"),
    distant_quarry_pipe=G("A steam pipe groaning and knocking in the distance.", 1.5, None, "far"),
    distant_derby_engine=G("Old V8 engines revving and two cars crunching together at a dirt demolition derby.", 2.5, None, "far"),
    distant_corn_rustle=G("Wind rustling through a tall dry cornfield, stalks knocking together.", 2.5, None, "far"),
    distant_mill_flume=G("Water rushing down a wooden flume and splashing into a pond.", 2.5, None, "far"),
    distant_quarry_blast=G("A dynamite blast rumbling and echoing across a rock quarry.", 2.5, None, "far"),
    crowd_cheer=G("A rowdy crowd whooping, hollering and clapping at a county fair stage.", 2.0, None, "crowd"),
    )

# ------------------------------------------------- bosses, brawls, the milk
# A boss's roar when it goes fightin' mad at half health and its holler going
# down (enemies.gd _enrage / _boss_falls); a fistfight between two of the
# county's hands; a hand slipping in the teat gun's milk.
add("alert",
    sheriff_rage=G("A rubbery B-movie alien sheriff shrieking in fury, warbling, electric and furious.", 1.6, None, "alien"),
    jerry_rage=G("A huge country man bellowing an angry roar like a furious football coach, then a sharp whistle blast.", 1.6, None, "vox"),
    rudy_rage=G("A crazed carnival barker cackling madly, then two blasts of a wheezy air horn.", 1.7, None, "creature"),
    foreman_rage=G("A hulking lumber-mill foreman roaring in rage over a chainsaw revving hard.", 1.6, None, "vox"),
    baron_rage=G("A pompous old moonshine baron bellowing furiously while steam pipes shriek around him.", 1.6, None, "vox"),
    )
add("death",
    sheriff_death=G("A rubbery alien's long dying wail that fizzles out into crackling electric sparks.", 2.2, None, "alien"),
    jerry_death=G("A huge country man's long dying groan ending in a heavy thud on the ground.", 2.0, None, "vox"),
    rudy_death=G("A carnival barker's long strangled howl ending in a deflating, wheezing honk.", 2.0, None, "creature"),
    foreman_death=G("A big man's dying bellow as a chainsaw sputters, coughs and dies.", 2.2, None, "vox"),
    baron_death=G("A pompous old man's dying wail as a copper boiler bursts with a hiss and a clang.", 2.2, None, "vox"),
    )
add("scene",
    brawl_punch=G("A meaty bare-knuckle punch to the jaw with a short grunt.", .5, None, "impact"),
    enemy_slip=G("A man's boots slipping in a puddle of milk: a wet squelch, a yelp and a heavy thud on the ground.", 1.2, None, "scene"),
    )

# ----------------------------------------------------------------------- ui
add("ui",
    menu_move=G("One tiny wooden tick, like a guitar pick tapping a fretboard.", .5, .09, "ui"),
    menu_accept=G("A short twangy guitar string pluck with a cash-drawer clunk.", .6, .22, "ui"),
    menu_back=G("A short low muted guitar string thunk, falling.", .5, .16, "ui"),
    empty=G("A dull rattle of a locked door handle: short denied clunk.", .5, .15, "ui"),
    )

# -------------------------------------------------------------------- music
add("sting",
    shakedown_intro=G("A menacing low twang guitar slide into a hard drum hit: boss arrival sting.", 2.5, 2.2, "sting"),
    shakedown_end=G("A triumphant twangy guitar lick ending on a big ringing chord: boss defeated sting.", 2.5, 2.2, "sting"),
    rudy_intro=G("A crooked carnival organ run crashing into a rockabilly guitar stab: boss arrival sting.", 2.5, 2.2, "sting"),
    rudy_end=G("A rockabilly guitar flourish with a comic slide-whistle fall and final chord.", 2.5, 2.2, "sting"),
    foreman_intro=G("A heavy blues guitar riff with an anvil clang: boss arrival sting.", 2.5, 2.2, "sting"),
    foreman_end=G("A heavy blues guitar lick resolving on a big ringing chord with a final drum crash.", 2.5, 2.2, "sting"),
    baron_intro=G("A dark Southern rock riff with a steam whistle and pounding toms: final boss arrival sting.", 2.5, 2.2, "sting"),
    baron_end=G("A huge victorious Southern rock final chord with a rolling drum fill.", 2.5, 2.2, "sting"),
    got_bessie=G("A happy pig oinks and squeals with delight.", 1.4, 1.2, "creature"),
    jerry_intro=G("A marching-band drumline roll and a rude trombone blat.", 1.4, 1.1, "creature"),
    )
add("jukebox",
    jukebox=LOOP("An old honky-tonk country shuffle playing from a small jukebox speaker: twangy guitar, walking bass, brushed drums, tinny and warm. Instrumental.", 24, 24.0, "sting"),
    )

# ---------------------------------------------------------------- the voices
# The text is the caption shown in game (campaign/chatter tables); it is spoken
# as written. "radio", "pa" and "horn" are the speaker the line comes out of.
add("voice",
    county_dispatch_0=V("Look for the hog.", "dispatch", "radio"),
    county_dispatch_1=V("The hog is home.", "dispatch", "radio"),
    county_dispatch_2=V("Check the blue trunk.", "dispatch", "radio"),
    county_dispatch_3=V("Keep the last load.", "dispatch", "radio"),
    county_dispatch_4=V("Check the bayou.", "dispatch", "radio"),
    talk_tow__radio_0=V("Who took the truck?", "dispatch", "radio"),
    talk_tow__radio_1=V("Ask the pig.", "local", say="Ask the pig. I said, ask the pig. Go ask the pig."),
    talk_registry__radio_0=V("Keep the key dry.", "dispatch", "radio"),
    talk_registry__radio_1=V("Then fix the roof.", "local"),
    talk_freight__pa_0=V("Save that rope.", "barker", "pa"),
    talk_freight__pa_1=V("For the show?", "local"),
    talk_show__pa_0=V("Clear the stage.", "barker", "pa"),
    talk_show__pa_1=V("Tell the goat.", "local"),
    talk_sort__radio_0=V("Hear that belt?", "dispatch", "radio"),
    talk_sort__radio_1=V("Sounds like teeth.", "local"),
    talk_kiln__radio_0=V("Kill the drive.", "dispatch", "radio"),
    talk_kiln__radio_1=V("You first.", "local"),
    talk_pit__speaker_0=V("Taste that mud?", "barker", "horn"),
    talk_pit__speaker_1=V("Needs more salt.", "local"),
    talk_line__speaker_0=V("Close the tap.", "barker", "horn"),
    talk_line__speaker_1=V("Which red one?", "local"),
    )


# ------------------------------------------- chapters five to seven, the range
# From docs/new_chapters/<chapter>_audio.md and docs/quest_props_audio.md. A new
# cue has no older cue to take its length from, so each keeps what it asks for.
def N(prompt, gen, keep=None, style="mech", **opts):
    return G(prompt, gen, keep if keep is not None else gen, style, **opts)


# Gator Bayou (chapter five): the noodler, the chum tosser, the gator, the Swamp King.
add("alert",
    noodler_holler=N("A big swamp man hollers, startled and mean, a wet bark of a shout rising out of the water.", 1.0, style="vox"),
    chum_holler=N("A bait man yells \"Chum's in!\" and sloshes a bucket, slop hitting the water.", 1.2, style="vox"),
    king_holler=N("A big redneck swamp boss whoops over a roaring airboat engine, \"Who's on my water?\"", 1.6, style="vox"),
    swamp_king_rage=N("A fat swamp king bellows furiously over a redlining airboat engine.", 1.6, style="vox"),
    )
add("warn",
    noodler_grunt=N("A heavy man grunts and winds up a swing, a big wet fish slapping against his waders.", .8, style="creature"),
    chum_slosh=N("A plastic jug of fish chum sloshed back over a shoulder to throw: thick liquid glug.", .7, style="impact"),
    gator_hiss=N("An alligator's low warning hiss and throat rumble, close.", 1.0, style="creature"),
    king_rev=N("An airboat's aircraft engine revving hard, the big caged propeller winding up to a roar.", 1.2, style="tool"),
    )
add("attack",
    noodler_slap=N("A huge wet catfish slammed across somebody: meaty slap, splatter of swamp water.", .6, style="impact"),
    chum_throw=N("A full jug of chum lobbed: effortful toss, the jug tumbling with a gurgle.", .6, style="impact"),
    gator_snap=N("An alligator's jaws snapping shut hard: heavy clack and a lunge splash.", .6, style="creature"),
    king_charge=N("An airboat launching flat out across water: engine howl, prop roar, a hissing rooster tail of spray.", 1.4, style="tool"),
    king_ram=N("A steel airboat hull rams a wooden dock: heavy crunch, splintering planks, engine still screaming.", 1.0, style="impact"),
    king_beached=N("An airboat runs aground on a mud bank: grinding scrape, the engine choking and sputtering down.", 1.3, style="impact"),
    king_puntgun=N("A huge punt gun fires from a boat: enormous black-powder boom, a spray of shot ripping across water.", 1.4, .9, "gun"),
    )
add("scene",
    noodler_rise=N("A big man bursts up out of shallow swamp water: heavy splash, water pouring off him.", 1.0, style="impact"),
    record_scratch=N("A needle dragged across a spinning record: a quick scratch to silence.", .6, style="mech"),
    )
add("death",
    king_down=N("A big man's dying howl as his airboat engine coughs and dies.", 1.8, style="vox"),
    swamp_king_death=N("A swamp king's last wail as his airboat's fuel tank goes up with a whump and a splash.", 2.2, style="vox"),
    )
add("sting",
    swamp_king_intro=N("Swampy dark Southern rock: a growling slide guitar riff, an airboat engine roar and pounding toms, boss arrival sting.", 2.5, 2.2, "sting"),
    swamp_king_end=N("A huge victorious Southern rock final chord with a washboard rattle and a rolling drum fill.", 2.5, 2.2, "sting"),
    )
add("ambience",
    amb_bayou=LOOP("A swamp at dusk: bullfrogs, cicadas and crickets, still water lapping at pilings, a far heron call.", 14, 14.0),
    amb_bayou_shack=LOOP("Inside a tin-roofed stilt shack: a box fan rattling, water lapping under the floor, insects on the screens.", 12, 12.0),
    amb_bayou_after=LOOP("A swamp gone quiet after a fight: frogs starting up again, drifting smoke, water settling.", 12, 11.6),
    )
add("distant",
    distant_bayou_airboat=N("An airboat engine idling out on open water far away.", 2.5, style="far"),
    distant_bayou_juke=N("A juke joint band thumping through thin walls across the water, muffled.", 2.5, style="far"),
    distant_bayou_gator=N("An alligator's deep bellow rolling across a swamp.", 2.0, style="far"),
    distant_bayou_frogs=N("A chorus of bullfrogs swelling far off in the cypress.", 2.0, style="far"),
    )
add("voice",
    talk_boil__cooks_0=V("Who dropped a boot in the boil?", "local"),
    talk_boil__cooks_1=V("That's seasonin'.", "dispatch", heard="That season in"),
    talk_juke__band_0=V("We know two songs.", "local"),
    talk_juke__band_1=V("Then play the other one.", "barker"),
    talk_dock__radio_0=V("King to dock. Fuel her up.", "barker", "radio", heard="King to doc, fuel her up"),
    talk_dock__radio_1=V("Tank's full, your majesty.", "local", heard="Thanks full, Your Majesty"),
    )

# Buzzard Bend Speedway (chapter six): the pit crew, the flagman, Bumper Boggs.
add("warn",
    derby_champ_warn=N("A big-block V8 in a battered derby car revving hard, lifters clattering, then the tyres starting to spin on dirt.", 1.2, style="tool"),
    huffer_hiss=N("A wild man huffing nitrous from a hose: a long gas hiss and a giggle.", 1.0, style="creature"),
    )
add("impact",
    derby_champ_crash=N("An armoured demolition-derby car slams into a concrete wall at speed: heavy crunch of steel, glass and a radiator bursting.", 1.4, style="impact"),
    lap_car_hit=N("A man struck by a speeding race car: bang of a fender and a body thrown onto dirt.", 1.0, style="impact"),
    )
add("alert",
    derby_champ_rage=N("A redneck derby champion bellowing from inside his car over a screaming engine and a horn blast.", 1.6, style="vox"),
    )
add("death",
    derby_champ_death=N("A derby car's engine dies in a tearing explosion: fuel tank whoomp, steel crumpling, a man's last holler.", 2.2, style="vox"),
    derby_champ_pain=N("A man inside a steel car grunting as bullets ping off the armour plate.", .8, style="vox"),
    derby_champ_down=N("A man inside a steel car gives a short dying groan as the engine coughs out.", 1.0, style="vox"),
    )
add("attack",
    flagman_flare=N("A flare pistol fired: hollow pop and a fizzing whoosh of a burning flare.", .8, style="gun"),
    tire_roll=N("A heavy racing tyre bowled hard along packed dirt: rubbery thump and a rumbling roll.", 1.2, style="impact"),
    wrench_throw=N("A heavy steel lug wrench thrown end over end: whoosh and a ringing clang where it lands.", .9, style="impact"),
    )
add("scene",
    # Close by the fence as the field comes round: the full band, not the distant chain.
    lap_car_pass=N("A dirt-track stock car blasting past close: V8 roar dopplering by, gravel spraying the wall.", 2.0, style="tool"),
    )
add("sting",
    derby_champ_intro=N("A gritty Southern rock riff over a revving V8 and a starter's horn: the derby champ rolls out.", 2.5, 2.2, "sting"),
    derby_champ_end=N("A huge victorious Southern rock chord with an engine coughing to silence and a crowd whoop.", 2.5, 2.2, "sting"),
    )
add("voice",
    talk_pit__radio_0=V("Fuel's a hundred and ten proof, boys.", "barker", "radio", heard="Fuel's 110 proof, boys"),
    talk_pit__radio_1=V("Then don't light a smoke.", "local"),
    talk_booth__pa_0=V("Lap forty-seven, Boggs leads.", "barker", "pa"),
    talk_booth__pa_1=V("As usual. What a shock.", "barker", "pa"),
    talk_camp__fire_0=V("See that saucer over turn two?", "local", heard="See that saucer overturned too"),
    talk_camp__fire_1=V("That's a floodlight, Earl.", "dispatch"),
    )

# The Mothership (chapter seven): the crew, the tin guard, the probe, Maw Glorb.
add("attack",
    drone_zap=N("A cattle prod jabbed into somebody: a crackling electric zap and a short buzz.", .7, .45, "alien"),
    guard_zapper=N("A giant bug zapper fired like a gun: three quick crackling purple bolts, fat and buzzy.", .8, .5, "alien"),
    probe_tug=N("A tractor beam yanks something: rising wobbling hum snapping into a zap.", .9, .6, "alien"),
    maw_dryer_blast=N("The giant hair dryer fires a fan of heat bolts: roaring hot whoosh with fizzing zaps.", 1.0, .7, "alien"),
    )
add("impact",
    tailgate_clang=N("A bullet ricochets off a rusty pickup truck tailgate: hard tinny clang and a whine.", .6, .35, "impact"),
    )
add("warn",
    maw_pin_raise=N("A giant raises a huge wooden rolling pin: creaking wood, a deep grunting inhale.", 1.1, .9, "creature"),
    maw_dryer_whine=N("A salon hair dryer the size of a car spinning up: rising whining fan and electric crackle.", 1.0, .85, "alien"),
    maw_stomp_warn=N("A huge creature lifts one foot in a fuzzy slipper: a creak of the deck and a building rumble.", 1.1, 1.0, "creature"),
    drone_buzz=N("A cattle prod charging: quick rising electric buzz.", .6, .4, "alien"),
    guard_wind=N("A huge bug zapper powering up: rising electric hum with crackling sparks.", .8, .6, "alien"),
    probe_whine=N("A small flying eyeball drone focuses its beam: rising wobbling theremin whine.", .8, .7, "alien"),
    )
add("boom",
    maw_pin_slam=N("A gigantic rolling pin slammed onto a steel deck: booming wooden thud, ringing metal, rattling floor plates.", 1.4, 1.0, "boom"),
    maw_stomp=N("A towering giant stomps a metal deck: deep booming quake, rattling bolts, a shockwave rolling out.", 1.6, 1.2, "boom"),
    )
add("alert",
    maw_holler=N("An enormous alien grandmother hollers to call her children in for supper, warbling and rubbery.", 1.4, 1.2, "alien"),
    maw_rage=N("A giant alien grandma shrieks in fury as her housecoat catches fire: warbling scream and crackling flames.", 1.8, 1.6, "alien"),
    maw_bare=N("A huge alien bellows with power cells humming up to full charge: furious roar over a rising electric whine.", 1.8, 1.6, "alien"),
    maw_spot=N("A huge alien grandma spots someone: a low suspicious \"hmmmm\" through a rubbery throat.", .9, .7, "alien"),
    probe_spot=N("A floating eyeball robot notices someone: quick curious beeping chirp.", .6, .4, "alien"),
    )
add("scene",
    pod_open=N("A crew pod's hatch hisses open: pressure hiss, wet suction pop, a chirp.", .9, .7, "alien"),
    beam_hum=N("A tractor beam touching someone: thick wobbling hum and a buzzing burn.", .9, .7, "alien"),
    )
add("death",
    maw_death=N("A towering alien grandmother's long dying wail, curlers clattering, ending in a crash and fizzling sparks.", 2.6, 2.4, "alien"),
    maw_pain=N("A giant alien grandma is hit: short indignant rubbery yelp.", .7, .5, "alien"),
    maw_down=N("A giant alien grandma falls: long warbling shriek and a floor-shaking thud.", 1.8, 1.5, "alien"),
    )
add("distant",
    ship_quake=N("A spaceship coming apart far off: groaning metal, a muffled explosion, rattling debris.", 2.5, 2.2, "far"),
    )
add("ambience",
    amb_mothership=LOOP("Inside a junky alien mothership: low engine drone, ticking hull, bubbling tanks, a faint distant moo.", 12, 12.0),
    )
add("sting",
    maw_intro=N("A menacing cowpunk riff with a theremin wail and a slammed screen door: final boss arrival sting.", 2.5, 2.2, "sting"),
    maw_end=N("A huge triumphant cowpunk final chord with a falling theremin and a cymbal crash: the last boss is down.", 3.0, 2.6, "sting"),
    )
add("voice",
    # The ship's PA is Maw herself: she runs the place.
    talk_ship__pa_0=V("Hooman loose on deck four.", "maw", "pa", heard="Human loose on deck four"),
    talk_ship__pa_1=V("Which one is the hooman?", "local", heard="Which one is the Who man"),
    talk_mess__pa_0=V("Corn dogs are off.", "maw", "pa"),
    talk_mess__pa_1=V("Again?", "local", say="Again? Again."),
    talk_engine__pa_0=V("Who put diesel in the drive?", "maw", "pa"),
    talk_engine__pa_1=V("Sign said unleaded.", "local"),
    talk_bridge__pa_0=V("Where's my boy's tin star?", "maw", "pa"),
    talk_bridge__pa_1=V("Hickston, Maw.", "local", heard="Hixton Mall"),
    # The Crossroads board's lines past the quarry (game_state.gd HUB_DISPATCH 4-7;
    # 6 is the old 4's take, copied: the table grew two chapters in the middle).
    county_dispatch_5=V("Check the speedway.", "dispatch", "radio"),
    county_dispatch_6=V("The tag is home.", "dispatch", "radio"),
    county_dispatch_7=V("Nothing up there but stars.", "dispatch", "radio"),
    )

# Mundell's Proving Grounds, the firing range (docs/new_chapters/range_audio.md).
add("impact",
    range_gong=N("A steel gong target struck by a rifle bullet at 20 yards: bright metallic clang ringing out, outdoors.", 1.4, style="impact"),
    range_board_hit=N("A bullet punching through a plywood bullseye target on a wooden stand: dry crack and a wobble of the stand.", .5, style="impact"),
    range_pin_scatter=N("Bowling pins scattering on a wooden lane, a full strike: hollow wooden clatter.", 1.2, style="impact"),
    )
add("melee",
    range_dummy_thwack=N("A crowbar thwacking a straw-stuffed feed-sack dummy: dull burlap thump with straw rustle.", .5, style="impact"),
    )
add("ui",
    range_strike=N("A county-fair bell and a short brass \"ta-da\" for a bowling strike, cheerful and cheap.", 1.5, style="ui"),
    range_gallery_ding=N("A tin shooting-gallery duck knocked flat: a high tin ping and a spring clack.", .5, .4, "ui"),
    range_gallery_buzzer=N("An old carnival game buzzer ending the round: a rattly electric buzz.", 1.0, style="ui"),
    )
add("station",
    range_lever=N("A heavy iron release lever thrown on a fence-post switch box: clunk and ratchet.", .6, style="tool"),
    # The quest props' knife lever (a station's default cue, level.gd).
    lever_clunk=N("A big knife-switch lever on a steel control box thrown down hard: heavy clunk and a spring twang.", .7, style="tool"),
    )
add("door",
    range_pen_gate=N("A wooden livestock pen gate banging open on its chain.", .8, style="mech"),
    # A locked exit or gate shaken: chain and padlock (docs/quest_props_audio.md).
    chain_rattle=N("A heavy chain and padlock on a gate yanked and rattled, locked tight.", .8, style="mech"),
    )
add("voice",
    range_pa_hot=V("The range is hot. Keep it pointed downrange, y'hear.", "local", "pa",
                  heard="The range is hot. Keep it pointed down range, you hear"),
    range_pa_medic=V("Medic to the firing line. Again.", "local", "pa"),
    )
add("ambience",
    amb_range=LOOP("A thin county-fair crowd at dusk far off: murmur, a distant calliope, crickets, the odd whoop.", 20, 20.0),
    )

# --------------------------------------- things breaking, impacts, weather
# The sounds docs/physics_audio.md, docs/feel_audio.md and docs/visual_audio.md
# listed for the breakables, the struck materials, the gun's feel, the weather,
# the water and the heat spots (2.0.0-dev.32). Each keeps what it asks for.
add("scene",
    break_crate=N("A wooden shipping crate shot to pieces: a dry splintering crack and loose boards clattering down onto dirt.", 1.0, style="scene"),
    break_barrel=N("An old oak whiskey barrel staved in: a heavy wooden crunch, staves falling and an iron hoop ringing as it drops.", 1.2, style="scene"),
    break_mash=N("A wooden barrel of sour corn mash split open: a cracking stave, then a thick wet slosh pouring out onto the ground.", 1.2, style="scene"),
    break_jugs=N("Three clay moonshine jugs shattering at once: crockery bursting, shards tinkling, liquor splashing.", 1.0, style="scene"),
    break_jar=N("A big glass specimen jar bursting: a heavy glass pop and brine gushing and splattering on the floor.", 1.2, style="scene"),
    break_cooler=N("A plastic picnic cooler shot open: hollow plastic crack, the lid clattering off, beer cans rolling out.", 1.0, style="scene"),
    break_tin=N("Tin cans and a tin mailbox shot off a post: bright tinny clanks rattling down onto gravel.", 1.0, style="scene"),
    break_flamingo=N("A plastic lawn flamingo shot and knocked over: one hollow plastic clack and a light bounce.", .6, style="scene"),
    break_stuffing=N("A plush carnival prize bear burst by a shot: a soft fabric thump and a puff of stuffing and straw.", .8, style="scene"),
    balloon_pop=N("A string of carnival balloons popping in a quick ragged run, four or five sharp pops.", .8, style="scene"),
    alien_crate_break=N("An alien cargo pod bursting open: a buckling metal crunch and a wet rubbery squelch.", 1.2, style="alien"),
    break_window=N("A dusty old storefront window shot out: a sharp crack, then big glass shards raining down and tinkling on boards.", 1.2, style="scene"),
    break_fence=N("Weathered wooden fence boards blown out by a shotgun: splintering crack, boards snapping and clattering down.", 1.0, style="scene"),
    sign_shot=N("A bullet smacking into a painted wooden sign: one sharp hollow wooden knock and a little rattle.", .5, style="impact"),
    debris_settle=N("Small splinters, glass bits and scraps of tin landing and settling on the ground, a light scattered patter.", .8, style="scene"),
    tnt_roll=N("A single stick of dynamite rolling across wooden boards: a light hollow papery roll and two small knocks.", .8, style="scene"),
    )
add("impact",
    body_thud=N("A limp body thrown down hard on dirt and boards: one heavy dull thud.", .6, style="impact"),
    bowling_thud=N("A heavy bowling ball slamming into a wooden wall, then rumbling away across boards.", .9, style="impact"),
    ricochet_tin=N("A bullet striking corrugated sheet tin: a thin bright metallic ping with a short buzz.", .6, style="impact"),
    ricochet_whine=N("A bullet glancing off thick steel plate: a hard clank and a long whining ricochet flying off.", 1.0, style="impact"),
    impact_brick=N("A bullet striking an old brick wall: a dry crack and a patter of grit and brick dust.", .5, style="impact"),
    impact_glass=N("A bullet cracking a thick window pane without breaking it out: a sharp tick and a small glassy tinkle.", .6, style="impact"),
    impact_brush=N("A bullet tearing through dry cornstalks and brush: a quick rustling thwip.", .5, style="impact"),
    impact_mesh=N("A bullet striking a taut wire farm fence: a metallic twang that wobbles out.", .6, style="impact"),
    impact_rubber=N("A bullet thumping into a stack of old car tyres: one dull rubbery thud.", .5, .4, style="impact"),
    pierce_plank=N("A rifle bullet punching clean through a plank wall: a splintering crack and wood chips spraying out the far side.", .5, style="impact"),
    glass_settle=N("Small chips of broken window glass falling and settling on a wooden floor: a light tinkling scatter.", .8, style="scene"),
    )
add("player",
    land_thump=N("A man in heavy work boots landing from a jump onto dirt: one solid boot thump with a little grunt of breath.", .5, .4, style="foot"),
    blow_grunt=N("A tough redneck man takes a light punch and grunts once, short and annoyed.", .5, .4, style="vox"),
    )
add("station",
    fuse_short=N("A short sharp fuse sizzle, a quick fizzing hiss that cuts off, just before something blows.", .5, .4, style="mech"),
    )
add("foot",
    wade_splash=N("A man in boots stepping heavily into knee-deep swamp water: one big slosh and splash.", .7, style="foot"),
    drip_small=N("A few single water drips falling into a still swamp puddle, quiet and close.", .6, style="foot"),
    )
add("weather",
    rain_loop=LOOP("Steady moderate rain falling outdoors at night on dirt, puddles, tin roofs and parked truck hoods, no thunder.", 20, 20.0, "amb"),
    rain_roof=LOOP("Steady rain drumming on a tin roof heard from inside a wooden shed: a muffled close drumming, no thunder.", 15, 15.0, "amb"),
    )
add("near",
    fire_crackle=LOOP("A wood fire burning in a rusty steel burn barrel: crackles, pops and a soft roar, close.", 10, 10.0, "amb"),
    ember_crackle=LOOP("Embers and a small wood fire crackling softly, little pops and a faint hiss, close.", 8, 8.0, "amb"),
    still_bubble=LOOP("A copper moonshine still on a fire: low steady bubbling mash, dripping and the tick of hot copper.", 8, 8.0, "amb"),
    generator_hum=LOOP("A small gasoline generator running steadily: a putt-putting single-cylinder engine with a rattle.", 6, 6.0, "tool"),
    core_thrum=LOOP("A deep slow pulsing alien power core: a low throbbing thrum with a faint warbling shimmer on top.", 10, 10.0, "alien"),
    airboat_wake=LOOP("The hiss and slap of a fast boat's wake on swamp water: rushing water and spray, no engine.", 6, 6.0, "amb"),
    )

# The bosses talking (2.0.0-dev.33, features/boss_voices.gd): a line when the
# fight starts, two taunts when they hurt the player, a worried one at their
# last phase and a last word as they fall. The caption is the text.
BOSS_LINES = {
    "sheriff": ("sheriff", ["You're under arrest, Earth boy.", "Resistin' arrest, I see.",
                            "That's a citation, son.", "Backup! I need backup!",
                            "Tell my saucer... I loved her."]),
    "jerry": ("jerry", ["Son, you're on my field now.", "Run it again, boy!", "That's a penalty!",
                        "Somebody get me a towel.", "Coach always said... hustle."]),
    "rudy": ("barker", ["Step right up and lose, sucker!", "Ain't nobody wins this game!",
                        "Three tries for a dime!", "Folks, the show's runnin' long...",
                        "The show's... over... folks."]),
    "foreman": ("foreman", ["You're on the clock, slacker.", "Back to work!",
                            "That's comin' outta your pay!", "Somebody kill that dang saw!",
                            "I'm... clockin' out."]),
    "baron": ("baron", ["Nobody drinks my shine for free.", "Aged twelve years, like my temper!",
                        "You'll be pickled by sundown.", "My stills! Not my stills!",
                        "Bury me... in a barrel."]),
    "swamp_king": ("swamp_king", ["Who's on my water?", "Gator bait, that's all you are!",
                                  "Ride's free, landin's extra!", "She's takin' on water!",
                                  "Tell the gators... I'm comin' home."]),
    "boggs": ("boggs", ["Buckle up, sunshine!", "Trade paint with me, boy!",
                        "Forty-seven wins and countin'!", "Radiator's blown, dang it!",
                        "Checkered flag... for me..."]),
    "maw": ("maw", ["Who tracked mud on my clean deck?", "Eat your vegetables, hooman!",
                    "Wait till your father lands!", "My curlers! Not my curlers!",
                    "Tell my young'uns... supper's cold."]),
}
BOSS_MOMENTS = ["intro", "taunt_0", "taunt_1", "worried", "last"]
# How a line's transcript spells words the caption writes the county's way.
BOSS_HEARD = {
    "boss_sheriff_taunt_0": "Resist an arrest, I see",
    "boss_rudy_worried": "Folks, the show's running long!",
    "boss_foreman_taunt_1": "That's coming out of your pay",
    "boss_foreman_last": "I'm clocking out",
    "boss_baron_taunt_0": "Aged 12 years, like my temper",
    "boss_swamp_king_taunt_1": "Rides free, landings extra",
    "boss_swamp_king_worried": "She's taking on water",
    "boss_swamp_king_last": "Tell the gators I'm coming home",
    "boss_boggs_taunt_1": "47 wins and counting",
    "boss_maw_taunt_0": "Eat your vegetables, human",
}
add("voice", **{f"boss_{who}_{moment}": V(text, voice, **({"heard": BOSS_HEARD[f"boss_{who}_{moment}"]}
                                                       if f"boss_{who}_{moment}" in BOSS_HEARD else {}))
                for who, (voice, lines) in BOSS_LINES.items()
                for moment, text in zip(BOSS_MOMENTS, lines)})

# Chapter music: (stem, title, bpm, prompt). Three per chapter, shuffled.
BAND = ("Instrumental 1990s cowpunk bar band recorded live in a small room: twangy overdriven "
        "Telecaster lead with a bright biting treble tone, second crunchy rhythm guitar, slap upright bass, snappy cracking snare and lively acoustic drums. Up-tempo and urgent. "
        "Gritty, mischievous, swaggering, lo-fi but punchy. No vocals, no synths. "
        "Clear hook riff, a contrasting middle section, then the hook returns bigger and ends on a hard stop.")
MUSIC = [
    ("music", "County Road Shuffle", 148, "Dusty roadside swagger: a swinging shuffle with a cocky twangy guitar hook and walking slap bass, small-town mischief."),
    ("county_line", "County Line at Sundown", 132, "Loping roadhouse boogie at sundown: lazy bent-note guitar hook, tremolo chords in the middle, swinging bass."),
    ("porchlight_stomp", "Porchlight Stomp", 168, "Fast front-porch stomp: chicken-picked guitar hook, train-beat snare, hoedown energy with a half-time breakdown."),
    ("fair_score", "The Wheel Turns Crooked", 176, "Energetic rockabilly with a crooked carnival feel: reverb-drenched guitar hook, a wheezy off-kilter waltz break like a broken calliope played on guitar, then full tilt again."),
    ("tickets_after_dark", "Tickets After Dark", 158, "Sneaky midway rockabilly at night: minor-key tremolo guitar hook, playful tension, tom-tom jungle beat, surf-style stabs."),
    ("closing_time_shuffle", "Last Call at the Midway", 184, "Rowdy psychobilly closing-time rave-up: frantic slap bass, galloping drums, wild bending guitar hook, a stop-time middle section."),
    ("mill_score", "Rain on the Green Chain", 112, "Heavy swampy blues-rock grind: thick fuzzy slide guitar riff, pounding floor toms, anvil-like metal clanks on the backbeat, rough lumberyard muscle."),
    ("green_chain", "Green Chain Blues", 126, "Mid-tempo dirty blues shuffle: growling low-string guitar riff, harmonica-like bent guitar answers, chugging mechanical rhythm like a saw carriage."),
    ("apron_run", "Across the Loading Apron", 152, "Driving boogie-rock work song: relentless palm-muted riff, cowbell and clanking metal percussion, big gang-riff return."),
    ("quarry_score", "Limestone Stomp", 120, "Dark Southern rock stomp: detuned heavy riff, pressure-building pedal bass, tambourine and chain percussion, ominous twang."),
    ("copper_and_steam", "Copper and Steam", 140, "Tense dark Southern rock: sinister tremolo-picked riff over a driving bass ostinato, hissing hi-hats, a slow-burn middle that builds like boiler pressure."),
    ("last_load", "Last Load from Stillwater", 164, "Full-throttle industrial Southern rock finale: pounding double-time drums, snarling dual guitars, hammering metal hits, a huge climactic hook return."),
    # Gator Bayou: a fish camp on black water, a juke joint, airboats.
    ("bayou_score", "Black Water Stomp", 112, "Swampy dark Southern rock at dusk: a greasy slide guitar riff over a loping kick and washboard, a growling bass, jug blows and a lonesome harmonica answering; humid, muddy and menacing, with a slow build like an airboat winding up out on the water."),
    ("cypress_crawl", "Cypress Knee Crawl", 96, "Slow creeping swamp-blues crawl through the fog: a tremolo-soaked twangy guitar picking a sneaky minor riff, a moaning harmonica, a thumping jug bass, brushed snare with a washboard tick; a sly half-time middle with a dobro slide, then the riff comes back heavier."),
    ("crawdad_boil_hop", "Crawdad Boil Hop", 150, "Rowdy fish-camp juke-joint boogie at a crawfish boil: a hopping two-step beat with washboard and stomping kick, a squeezebox and a fiddle trading a greasy hook with the twangy guitar, slapping upright bass; a stop-time middle with jug blows, then full tilt."),
    # Buzzard Bend Speedway: dirt-track race night under floodlights, the pits, the derby.
    ("music_speedway", "Buzzard Bend Feature Race", 126, "Greasy Southern rock and honky-tonk at a dirt-track race night: driving overdriven Telecaster riff, chugging bass, snare on two and four with a ride cymbal like a revving engine, a wailing harmonica answering, a pedal steel swell over the bridge. Loose, loud, beer-soaked and fast."),
    ("pit_row_boogie", "Pit Row Boogie", 144, "Swaggering pit-row boogie: a chugging palm-muted guitar riff like an idling V8, cowbell and clanking wrench percussion on the backbeat, honky-tonk piano rolls, a slide guitar wailing through the turns; a grinding half-time breakdown, then the riff floors it."),
    ("checkered_flag_rag", "Checkered Flag Rag", 172, "Hell-for-leather train-beat hillbilly rock under the floodlights: a fast chicken-picked guitar hook, galloping slap bass, banjo rolls and honky-tonk piano racing each other, crash cymbals like a pile-up at the finish line; a stop-time middle, then a last lap even faster."),
    # The Mothership: a junky saucer run by B-movie greys and their grandma.
    ("mothership_score", "Abducted Hoedown", 136, "Dark, spooky cowpunk aboard a junky flying saucer: a B-movie theremin answering a twangy tremolo guitar hook, slap bass walking like a creeping alien, a clanking hull-plate backbeat; a half-time middle with a musical saw, then the hook returns bigger."),
]
# Seconds asked for a chapter track (scripts/audio_produce.py; the rest 140). The
# later chapters' are shorter: the game shuffles three of them.
MUSIC_LENGTH = {stem: 120 for stem in ("bayou_score", "cypress_crawl", "crawdad_boil_hop", "music_speedway",
                                       "pit_row_boogie", "checkered_flag_rag", "mothership_score")}
# Where a track's playback stops when the take ends past it (the game cuts
# there and moves on): music_speedway's take stops dead at 111.9 s and only
# hits one last stab four seconds of silence later.
MUSIC_END = {"music_speedway": 111.95}
# Fight music: (stem, title, bpm, prompt). One per chapter; the game swells it
# in over the chapter's track while enemies are on the player (sound.gd,
# features/fight_music.gd). Each take is cut into a seamless loop.
FIGHT_TAIL = ("Instrumental, no vocals, no synths. Full energy from the very first beat to the last: "
              "no intro, no fade-in, no breakdown, no ending, one steady tempo and key throughout so it "
              "loops seamlessly. Raw, gritty, lo-fi but punchy 1990s recording.")
FIGHTS = [
    ("fight_hickston", "Hickston Barn Burner", 172, "Fast small-town barn-burner hillbilly punk rock at 172 BPM: furious banjo rolls, sawing fiddle, twangy overdriven electric guitar riff, washboard scraping, thumping upright bass and stomping train-beat drums. Rowdy and reckless, a bar fight spilling into the street."),
    ("fight_fair", "Runaway Midway", 180, "Frantic carnival-midway hoedown punkabilly at 180 BPM: galloping slap bass, banjo and fiddle racing a wheezy off-kilter calliope organ riff, twangy reverb-soaked guitar stabs, washboard and crashing drums. Manic and crooked, like a runaway fairground ride."),
    ("fight_mill", "Ripsaw Stomp", 150, "Pounding industrial lumberjack stomp, country-metal at 150 BPM: buzzing distorted guitar riff that whines like a ripsaw biting a log, chugging palm-muted rhythm guitar, stomping kick and floor toms, anvil and chain clanks on the backbeat, fiddle stabs and driving banjo. Heavy, mechanical, relentless."),
    ("fight_quarry", "Stillwater Jug Brawl", 132, "Heavy moonshine-fuelled blues-rock at 132 BPM: grinding fuzz guitar riff, howling bottleneck slide guitar, booming jug bass blowing the low notes, stomping drums with tambourine and chain hits, frantic banjo answers. Dark, drunk and dangerous swamp-blues muscle."),
    ("fight_bayou", "Airboat Brawl", 136, "Heavy swamp-rock brawl at 136 BPM: fuzzed slide guitar riff, stomping drums with washboard and tambourine, a droning jug bass, frantic fiddle and harmonica stabs over a roaring overdriven riff. Loud, sweaty and dangerous."),
    ("fight_speedway", "Demolition Derby Brawl", 138, "Heavy redneck rock brawl at 138 BPM: crunching fuzz guitar riff, pounding floor toms and crash cymbals like cars colliding, slide guitar screaming over the top, honky-tonk piano hammering, a quick banjo roll on the turnarounds. Dangerous, sweaty and relentless."),
    ("fight_mothership", "Ray Gun Barn Dance", 176, "Frantic hillbilly punk at 176 BPM: furious banjo rolls and sawing fiddle against a wailing theremin riff, overdriven twang guitar, washboard and crashing train-beat drums. Manic, like a hoedown in a crashing spaceship."),
]
# Boss music: (stem, title, bpm, prompt). Each chapter's sound, faster and much
# heavier; it takes over from the chapter's track and fight loop while the
# boss fight is on (features/fight_music.gd; Maw Glorb's is features/mothership.gd).
# Cut into seamless loops like the fight music.
BOSSES = [
    ("boss_hickston", "Sheriff's Last Stand", 184, "Furious small-town hillbilly punk-metal showdown at 184 BPM: thundering train-beat drums with double kick, a heavy overdriven twang guitar riff, furious banjo rolls and a screaming fiddle, slapping upright bass, a slide guitar wailing like a squad car siren. Much faster and heavier than a bar fight: a jailhouse riot."),
    ("boss_fair", "Ringmaster Meltdown", 192, "Deranged carnival psychobilly-metal at 192 BPM: a wheezy off-kilter calliope organ riff doubled by a crunching heavy guitar, frantic slap bass, banjo and fiddle racing, crashing drums with double kick, rude honking horn stabs. A runaway midway on fire."),
    ("boss_mill", "Head Saw Showdown", 164, "Crushing fast sawmill country-metal at 164 BPM, the whole band flat out from the first bar: a buzzing ultra-heavy guitar riff that screams like a head saw biting oak, chugging palm-muted rhythm guitar, thunderous double kick and floor toms, anvil and chain clanks on every backbeat, fiddle stabs and driving banjo. Brutal, fast and mechanical."),
    ("boss_quarry", "Boil-Over at the Still", 150, "Ferocious moonshine swamp-blues metal at 150 BPM: a grinding detuned fuzz riff, howling bottleneck slide guitar, booming jug bass, stomping double-kick drums with chain hits and tambourine, a harmonica screaming like a steam whistle, frantic banjo. Heavier and faster than ever, a still about to blow."),
    ("boss_bayou", "Swamp King's Rampage", 168, "Ferocious swamp-metal stomp at 168 BPM: a growling fuzzed slide guitar riff that roars like an airboat engine, pounding double-kick drums and floor toms, washboard and tambourine slammed on every beat, a droning jug bass, harmonica and fiddle screaming over the top. Enormous, fast and heavy."),
    ("boss_speedway", "Bumper Boggs Wrecking Ball", 180, "Furious demolition-derby country-metal at 180 BPM: a crushing low-tuned guitar riff that revs like a big-block engine, a screaming slide guitar, pounding toms and crash cymbals like steel colliding, honky-tonk piano hammered hard, banjo rolls on the turnarounds. Heavy, fast and reckless."),
    ("boss_mothership", "Maw's Last Supper", 148, "The biggest, heaviest cut on the record: a thundering country-metal riff on detuned twangy baritone guitars, booming toms and anvil hits, a church-organ swell under a screaming theremin lead, a slide guitar howling back at it, the whole band slamming unison stabs. Relentless and epic, a hoedown at the end of the world."),
]
# Seconds asked for each loop: the fights and bosses 70, the last boss more.
LOOP_LENGTH = {"boss_mothership": 90}
VICTORY = ("victory", "A short celebratory cowpunk victory tune for a score tally screen: jubilant twangy "
           "guitar fanfare lick, slap bass and drums, playful and proud, ending on a big ringing final "
           "chord with a cymbal crash. " + BAND.split(" No vocals")[0] + " No vocals.", 14)

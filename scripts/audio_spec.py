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
  V(text, voice, fx)     a spoken line; `text` is the caption

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
    county_dispatch_4=V("The tag is home.", "dispatch", "radio"),
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
]
VICTORY = ("victory", "A short celebratory cowpunk victory tune for a score tally screen: jubilant twangy "
           "guitar fanfare lick, slap bass and drums, playful and proud, ending on a big ringing final "
           "chord with a cymbal crash. " + BAND.split(" No vocals")[0] + " No vocals.", 14)

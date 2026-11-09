"""Versioned single-slot checkpoint with no executable deserialization."""
from dataclasses import asdict, dataclass, fields
from datetime import datetime
from hashlib import sha256
import json
import math
import os
from pathlib import Path
import tempfile

from campaign import BY_ID, LEVELS
from campaign_score import SCORES
from enemies import Enemy
from game import AMMO, PICKUP_NAMES, PLAYER_RADIUS, TASK_ITEMS, Blast, Hazard, Shot, Speck
from hud import ITEMS
from weapons import CAPACITY, MAX_RESERVE, NAMES

VERSION = 4
SUPPORTED_VERSIONS = (1,2,3,VERSION)
EXPANSION_FIELDS = ("legacy_completed","legacy_key_route")
SLOT = "hickston-quick.json"
SETTINGS_FILE = "options.json"
UNLOCKS_FILE = "campaign-unlocks.json"
ENTRY_FILE = "campaign-entry.json"
ROAD_NOTES_FILE = "county-road-notes.json"
MANUAL_SLOTS = 4
LABEL_LENGTH = 24
@dataclass(frozen=True)
class Setting:
    label: str
    key: str
    default: int
    low: int
    high: int
    step: int = 1
    choices: tuple = ()
    hint: str = ""

    def format(self,value):
        return self.choices[value-self.low] if self.choices else f"{value}%"

    def adjust(self,value,direction):
        if self.choices:
            return self.low+(value-self.low+direction)%len(self.choices)
        return max(self.low,min(self.high,value+direction*self.step))


def choices(label,key,default,values,hint):
    return Setting(label,key,default,0,len(values)-1,1,values,hint)


def toggle(label,key,default,hint):
    return choices(label,key,default,("OFF","ON"),hint)


SETUP_PAGES = (
    ("INPUT",(
        Setting("MOUSE TURN SPEED","sensitivity",100,40,220,10,hint="HORIZONTAL MOUSE SPEED"),
        Setting("MOUSE LOOK SPEED","vertical",100,40,220,10,hint="VERTICAL MOUSE SPEED, INDEPENDENT OF TURN SPEED"),
        toggle("INVERT MOUSE Y","invert",0,"REVERSE UP AND DOWN MOUSE LOOK"),
        toggle("ALWAYS RUN","autorun",0,"SHIFT INVERTS RUN WHILE HELD"),
        choices("CROUCH","crouch",0,("HOLD","TOGGLE"),"HOW THE Z KEY CONTROLS CROUCHING"),
        toggle("PAUSE ON FOCUS LOSS","focus_pause",1,"PAUSE IF YOU SWITCH TO ANOTHER WINDOW"),
    )),
    ("DISPLAY",(
        Setting("BRIGHTNESS","brightness",100,80,150,10,hint="BRIGHTEN THE SCENE; HUD AND TEXT STAY FIXED"),
        choices("ASPECT / SCALING","aspect",0,("DOS 4:3","SQUARE 8:5","INTEGER 8:5"),"ALL MODES KEEP CRISP, UNSMOOTHED PIXELS"),
        choices("FRAME LIMIT","frame_limit",1,("30 FPS","60 FPS","120 FPS"),"LIMIT SCREEN REFRESH AND CPU USE"),
        choices("WINDOW MODE","window_mode",0,("WINDOWED","FULLSCREEN (FILL)","FULLSCREEN (ASPECT)"),
                "FILL REMOVES THE TITLE BAR AND ALL BLACK BARS"),
        choices("CROSSHAIR","crosshair",1,("OFF","DOT","RING"),"CHOOSE AN AIMING MARK"),
        choices("STATUS PANEL","hud_style",0,("METERS","DIALS"),"GAUGE STYLE FOR THE GUT AND DRUNK METERS"),
        Setting("WEAPON / VIEW BOB","bob",100,0,100,25,hint="REDUCE VIEW AND WEAPON SWAY WHILE WALKING"),
        choices("SCREEN FLASH","flashes",0,("FULL","REDUCED","OFF"),"REDUCE DAMAGE, MUZZLE AND BLAST FLASHES"),
    )),
    ("AUDIO",(
        Setting("MUSIC VOLUME","music",50,0,100,10,hint="BACKGROUND SCORE; F4 ALSO MUTES THE SCORE"),
        Setting("EFFECTS VOLUME","effects",100,0,100,10,hint="WEAPONS, MOVEMENT AND INTERACTIONS"),
        Setting("AMBIENCE VOLUME","ambience",100,0,100,10,hint="ROOMS, WIND, CREEK AND BACKGROUND ANIMALS"),
        Setting("FOOTSTEP VOLUME","footsteps",100,0,100,10,hint="PLAYER FOOTSTEPS AND LANDINGS"),
        Setting("VOICE VOLUME","voice_volume",80,0,100,10,hint="OVERHEARD RADIOS, SPEAKERS AND PA"),
        toggle("VOICE CAPTIONS","voice_captions",1,"TEXT FOR OVERHEARD LOCAL EXCHANGES"),
        choices("SFX STEREO WIDTH","stereo",2,("MONO","NARROW","NORMAL","WIDE"),"CONTROL HOW FAR POSITIONAL SOUNDS PAN"),
    )),
    ("PLAY",(
        choices("DIFFICULTY","difficulty",1,("EASY","NORMAL","HARD"),"ADJUSTS INCOMING DAMAGE IN THE CURRENT RUN"),
        choices("AIM ASSIST","aim_assist",0,("OFF","VERTICAL","CLASSIC"),"HELPS LINE UP VISIBLE TARGETS"),
        toggle("AUTO SWITCH ON PICKUP","auto_switch",1,"EQUIP A NEW WEAPON AS SOON AS YOU FIND IT"),
        toggle("RELOAD ON EMPTY","auto_reload",1,"FIRING AN EMPTY GUN STARTS RELOADING"),
        toggle("CLASSIC LEVEL FLOW","classic",0,"SKIP THE CROSSROADS. GO STRAIGHT TO THE NEXT CHAPTER."),
        toggle("PLAYER ONE-LINERS","barks",1,"SHOW THE HERO'S WISECRACKS"),
        toggle("BLOOD PARTICLES","gore",1,"SHOW BLOOD PARTICLES WHEN ENEMIES ARE HIT"),
        toggle("DISTRICT LABELS","district_labels",1,"SHOW LOCATION NAMES WHEN YOU ENTER NEW AREAS"),
        toggle("TOOLTIPS / OBJECTIVES","hints",1,"SHOW USE PROMPTS AND OBJECTIVES"),
        choices("NEXT RUN SUPPLIES","supply_rule",0,("STANDARD","SCARCE","NO DROPS"),
                "NEW RUNS ONLY. SCARCE CUTS BOXES. NO DROPS REMOVES BASIC FOE AMMO."),
    )),
    ("VIEW",(
        choices("SCENERY MOTION","world_motion",0,("FULL","REDUCED","STATIC"),
                "ADJUST MOTION IN CROSSROADS SCENERY"),
        choices("WEAPON POSITION","weapon_view",0,("STANDARD","LOWER","HIDDEN"),
                "LOWER OR HIDE WEAPON ART. LIT TNT STAYS VISIBLE."),
        toggle("BULLET MARKS","bullet_marks",1,"DRAW IMPACT MARKS ON WALLS"),
        toggle("DOS DITHER + COLOR WASH","retro_look",1,"ORDERED DITHER AND PER-CHAPTER COLOR GRADE"),
        toggle("LAMP FLICKER","flicker",1,"BUZZING LIGHTS INDOORS. TURN OFF IF SENSITIVE TO FLASHING."),
    )),
)
OPTIONS = tuple(option for _,page in SETUP_PAGES for option in page)
GAME_FIELDS = (
    "clock", "inventory_slot", "kills", "secrets", "face_until", "message_until",
    "face", "notice", "hurt_flash", "blast_flash", "sprint", "step_number", "next_belch",
    "map", "district", "district_until", "amb_clock", "jukebox_on", "flush_until",
)
ARM_FIELDS = ("active", "owned", "loaded", "reserve", "cooldown", "reload", "recoil",
              "flash", "switch", "empty", "shot_age", "last_spent", "holstered",
              "lower", "rifle_heat", "grinding", "swing_hit", "fuse", "tnt_latched")
DOOR_FIELDS = ("progress", "opened", "discovered")
ENEMY_FIELDS = tuple(f.name for f in fields(Enemy))
AI_FIELDS = ("route_slot", "patrol_pause", "recovery", "chase_turn",
             "see_time", "player_seen", "last_stride")
COMBAT_FIELDS = ("pressure_guard","volley","volley_timer","volley_angle","volley_slope")
EXTRA_GAME_FIELDS = ("radio_check", "wall_sound")
SHOT_KINDS = {"bolt", "blade", "arm_bolt", "plasma", "football", "tnt",
              "barker_bolt", "lantern_bolt", "bottle_rocket",
              "chalk_lob","rudy_horn","foreman_cut","deputy_slug","fair_bottle","chain_hook","valve_slug",
              "bowling","keg","cow","milk"}
SPECK_KINDS = {"spark","plasma","feather","gore","dust","glass","splash","chips","powder","soil"}
MAX_BYTES = 600_000


def data_directory():
    from resource_path import get_save_dir
    return Path(get_save_dir())


def selected(obj, keys):
    return {key: getattr(obj, key) for key in keys}


def snapshot(game):
    return {
        "version": VERSION, "level": game.level.id,
        "game": selected(game, GAME_FIELDS + EXTRA_GAME_FIELDS + ("won",) + EXPANSION_FIELDS),
        "player": asdict(game.player),
        "armory": selected(game.armory, ARM_FIELDS),
        "doors": {game.world.door_ids[d.x,d.y]: selected(d, DOOR_FIELDS) for d in game.world.doors},
        "enemies": {key: asdict(enemy) for key, enemy in zip(game.enemy_ids, game.enemies)},
        "ai": {key: {**selected(enemy, AI_FIELDS + COMBAT_FIELDS), "aim": enemy.aim_mark}
               for key, enemy in zip(game.enemy_ids, game.enemies)},
        "campaign": {"history": game.history, "entry": game.entry, "replay": game.replay},
        "county_gallery": bool(game.gallery and game.gallery.rewarded),
        "county_supplies": game.supply_rule,
        "county_reactions": {key: [enemy.heard,enemy.retreat,enemy.responded]
                             for key,enemy in zip(game.enemy_ids,game.enemies)
                             if enemy.heard or enemy.retreat or enemy.responded},
        "music": game.music_bookmark,
        "stations": sorted(game.stations_done),
        "tasks": sorted(game.task_items), "valve_turns": game.valve_turns,
        "scenery": sorted(game.scenery_spent), "heard": sorted(game.heard_exchanges),
        "shots": [asdict(shot) for shot in game.shots],
        "specks": [asdict(speck) for speck in game.specks],
        "blasts": [asdict(blast) for blast in game.blasts],
        "hazards": [asdict(hazard) for hazard in game.hazards],
        "inventory": game.inventory, "keys": sorted(game.keys),
        "drums": [(*point, hp) for point, hp in game.drums.items()],
        "pickups": game.pickups, "visited": sorted(game.visited),
        "panes": sorted(game.world.broken_panes),
        "rng": game.rng.getstate(),
    }


def write_atomic(path, data):
    if len(data) > MAX_BYTES:
        raise ValueError("Checkpoint is too large")
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile("w", encoding="utf-8", dir=path.parent, prefix=".checkpoint-",
                                         suffix=".tmp", delete=False) as writer:
            temporary = Path(writer.name)
            writer.write(data)
            writer.flush()
            os.fsync(writer.fileno())
        temporary.replace(path)
    finally:
        if temporary is not None and temporary.exists():
            temporary.unlink()


def save(game, path, manual=None):
    # NumPy map values are sometimes carried through to player coordinates or the district.
    def scalar(value):
        if type(value).__module__ == "numpy":
            return value.item()
        raise TypeError(f"Unexpected save value: {type(value).__name__}")
    doc = snapshot(game)
    if game.retained:
        doc["retained"] = {key:snapshot(chapter) for key,chapter in game.retained.items()}
    if manual is not None:
        doc["manual"] = manual
    data = json.dumps(doc, ensure_ascii=True, allow_nan=False, separators=(",", ":"), default=scalar)
    write_atomic(path,data)


def slot_directory(profile, replay_level=None):
    root = profile / "save-slots"
    return root / "replay" / replay_level if replay_level else root / "campaign"


def slot_label(text):
    return "".join(char for char in text.upper()
                   if char in "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 _.-'")[:LABEL_LENGTH]


def slot_bytes(path):
    try:
        with path.open("rb") as handle:
            return handle.read(MAX_BYTES+1)
    except FileNotFoundError:
        return None


def slot_metadata(path, replay_level=None):
    """Return the immutable file fingerprint with a bounded menu summary."""
    try:
        raw = slot_bytes(path)
        if raw is None:
            return None, None
        fingerprint = sha256(raw).hexdigest()
        require(len(raw)<=MAX_BYTES)
        doc = json.loads(raw)
        require(type(doc) is dict and doc.get("version") in (3,VERSION) and doc.get("level") in BY_ID)
        require(doc.get("campaign",{}).get("replay") is bool(replay_level)
                and (not replay_level or doc["level"]==replay_level))
        meta = doc.get("manual")
        require(type(meta) is dict and set(meta)=={"label","objective","timestamp"})
        name,goal,stamp = meta["label"],meta["objective"],meta["timestamp"]
        require(type(name) is str and name==slot_label(name).strip() and bool(name))
        require(type(goal) is str and len(goal)<=100 and type(stamp) is str and len(stamp)<=32)
        timestamp = datetime.fromisoformat(stamp)
        require(timestamp.tzinfo is not None)
        return fingerprint, (name,doc["level"],goal,timestamp.astimezone().strftime("%Y-%m-%d %H:%M"))
    except (OSError,ValueError,TypeError,AttributeError,RecursionError,OverflowError):
        return "", None


def save_named(game, path, name, fingerprint):
    name = slot_label(name).strip()
    require(name and fingerprint!="")
    path.parent.mkdir(parents=True,exist_ok=True)
    lock = path.with_suffix(".lock")
    with lock.open("a+b") as handle:
        handle.seek(0)
        if os.name=="nt":
            import msvcrt
            msvcrt.locking(handle.fileno(),msvcrt.LK_NBLCK,1)
        else:
            import fcntl
            fcntl.flock(handle,fcntl.LOCK_EX|fcntl.LOCK_NB)
        previous = slot_bytes(path)
        require((sha256(previous).hexdigest() if previous is not None else None)==fingerprint)
        save(game,path,{"label":name,"objective":game.objective()[:100],
                        "timestamp":datetime.now().astimezone().isoformat(timespec="seconds")})


def settings(path=None):
    try:
        raw = path.read_bytes()[:4096] if path and path.is_file() else b"{}"
        values = json.loads(raw)
    except (ValueError,OSError,RecursionError):
        values = {}
    if not isinstance(values,dict):
        values = {}
    if "window_mode" not in values and values.get("startup_fullscreen") == 1:
        values["window_mode"] = 1
    return {o.key:min(o.high,max(o.low,values[o.key])) if type(values.get(o.key)) is int else o.default
            for o in OPTIONS}


def save_settings(path,values):
    write_atomic(path,json.dumps(values,separators=(",",":")))


def unlocks(path=None):
    if path:
        try:
            data = json.loads(path.read_bytes()[:4096])
            if isinstance(data, list):
                result = {"hickston"}
                for level in LEVELS[1:]:
                    if level.id not in data:
                        break
                    result.add(level.id)
                return result
        except (OSError, ValueError, RecursionError):
            pass
    return {"hickston"}


def save_unlocks(path, unlocked):
    write_atomic(path, json.dumps([level.id for level in LEVELS if level.id in unlocked]))


def road_notes(path):
    try:
        raw = json.loads(path.read_bytes()[:1024]) if path else []
    except (OSError,ValueError,RecursionError):
        return set()
    return {key for key in raw if key in ("ledger","survey")} if isinstance(raw,list) else set()


def save_notes(path,notes):
    write_atomic(path,json.dumps(sorted(notes)))


def require(condition):
    if not condition:
        raise ValueError("Invalid or incompatible checkpoint")


def numeric(value):
    return type(value) in (int, float) and -1e7 <= value <= 1e7


def restore_attributes(obj, values, keys):
    require(isinstance(values, dict) and set(values) == set(keys))
    for key in keys:
        before, value = getattr(obj, key), values[key]
        if type(before) is bool:
            require(type(value) is bool)
        elif isinstance(before, str):
            require(isinstance(value, str) and len(value) <= 128)
        elif before is None:
            require(value is None or isinstance(value, list) and len(value) == 2 and all(map(numeric, value)))
            value = None if value is None else tuple(value)
        elif isinstance(before, list):
            typ = bool if key == "owned" else int
            require(isinstance(value, list) and len(value) == len(before) and all(type(x) is typ for x in value))
        elif type(before) is int:
            require(type(value) is int and numeric(value))
        else:
            require(numeric(value))
        setattr(obj, key, value)


def restore_list(values, factory, kinds, cap):
    require(isinstance(values, list) and len(values) <= cap)
    keys = {f.name for f in fields(factory)}
    for row in values:
        require(isinstance(row, dict) and set(row) == keys and row["kind"] in kinds)
        for key,value in row.items():
            require(type(value) is bool if key in ("enemy","resting") else
                    key == "kind" or numeric(value))
    return [factory(**row) for row in values]


def upgrade_kit(kit):
    """Pad pre-2.0 loadouts (12 weapons, 3 items) with the new slots."""
    if isinstance(kit, dict) and isinstance(kit.get("owned"), list):
        for key in ("owned","loaded","reserve"):
            values = kit.get(key)
            if isinstance(values, list) and len(values) < len(NAMES):
                values.extend([False if key=="owned" else 0]*(len(NAMES)-len(values)))
        inv = kit.get("inventory")
        if isinstance(inv, dict):
            for name in ITEMS:
                inv.setdefault(name, 0)
    return kit


def validate_kit(kit):
    upgrade_kit(kit)
    require(isinstance(kit, dict)
            and set(kit) == {"health", "owned", "loaded", "reserve", "active", "inventory", "slot"})
    require(type(kit["health"]) is int and 1 <= kit["health"] <= 100)
    owned = kit["owned"]
    require(isinstance(owned, list) and len(owned) == len(NAMES)
            and all(type(value) is bool for value in owned) and owned[0])
    require(type(kit["active"]) is int and 0 <= kit["active"] < len(NAMES) and owned[kit["active"]])
    for key, limits in (("loaded", CAPACITY), ("reserve", MAX_RESERVE)):
        values = kit[key]
        require(isinstance(values, list) and len(values) == len(limits)
                and all(type(n) is int and 0 <= n <= limit for n, limit in zip(values, limits)))
    require(type(kit["slot"]) is int and 0 <= kit["slot"] < len(ITEMS))
    require(isinstance(kit["inventory"], dict) and set(kit["inventory"]) == set(ITEMS)
            and all(type(n) is int and 0 <= n <= 5 for n in kit["inventory"].values()))
    return kit


def pad_armory(values,armory,size):
    require(isinstance(values,dict))
    for key in ("owned","loaded","reserve"):
        require(isinstance(values.get(key),list) and len(values[key])==size)
        values[key] += getattr(armory,key)[size:]
    require(type(values.get("active")) is int and 0<=values["active"]<size)


def clear_legacy_position(world, x, y, heading, radius, fallback):
    if not world.blocked(x,y,radius):
        return x,y
    for distance in (.25,.5,.75,1.,1.5,2.):
        for index in range(8):
            angle = heading + index * math.tau / 8
            xx,yy = x+distance*math.cos(angle),y+distance*math.sin(angle)
            if not world.blocked(xx,yy,radius+.06):
                return xx,yy
    return fallback


def read(path, make_game, *, migrate=False, expected_replay=None, expected_level=None):
    with path.open("rb") as handle:
        raw = handle.read(MAX_BYTES+1)
    require(len(raw) <= MAX_BYTES)
    doc = json.loads(raw)
    require(isinstance(doc, dict) and type(doc.get("version")) is int and doc["version"] in SUPPORTED_VERSIONS)
    version = doc["version"]
    game = restore(doc, make_game, expected_replay)
    require(expected_level is None or game.level.id==expected_level)
    if version >= 3:
        retained = doc.get("retained", {})
        previous = {level.id for level in LEVELS[:LEVELS.index(game.level)]}
        require(isinstance(retained,dict) and set(retained) <= (set() if game.replay else previous))
        for key, chapter in retained.items():
            require(isinstance(chapter,dict) and chapter.get("version")==version
                    and chapter.get("level")==key and "retained" not in chapter)
            restored = restore(chapter,make_game,False)
            require(restored.won)
            game.retained[key] = restored
    if version != VERSION and migrate:
        digest = sha256(raw).hexdigest()[:16]
        backup = path.with_name(f"{path.stem}.v{version}-{digest}.bak")
        if not backup.exists():
            with backup.open("xb") as handle:
                handle.write(raw)
                handle.flush()
                os.fsync(handle.fileno())
        require(backup.read_bytes() == raw and path.read_bytes() == raw)
        save(game,path,doc.get("manual"))
    return game


def restore(doc,make_game,expected_replay):
    version = doc["version"]
    legacy = version == 1
    level_id = "hickston" if legacy else doc["level"]
    require(isinstance(level_id, str) and level_id in BY_ID)
    game = make_game() if level_id == "hickston" else make_game(level_id)
    require(game.level.id == level_id)
    w = game.world
    valid_position = lambda x,y: numeric(x) and numeric(y) and 0 <= x < w.solid.shape[1] and 0 <= y < w.solid.shape[0]
    fields_game = GAME_FIELDS if legacy else GAME_FIELDS + EXTRA_GAME_FIELDS
    if version >= 3:
        fields_game += ("won",)
    if version == VERSION:
        fields_game += EXPANSION_FIELDS
    restore_attributes(game, doc["game"], fields_game)
    reward = doc.get("county_gallery",False)
    require(type(reward) is bool and (not reward or game.gallery is not None))
    if game.gallery:
        game.gallery.rewarded = reward
    game.supply_rule = doc.get("county_supplies",0)
    require(type(game.supply_rule) is int and game.supply_rule in (0,1,2))
    restore_attributes(game.player, doc["player"], tuple(f.name for f in fields(game.player)))
    armory = doc["armory"]
    if isinstance(armory, dict):
        for key in ("owned","loaded","reserve"):
            if isinstance(armory.get(key), list) and version >= 3 and len(armory[key]) < len(NAMES):
                armory[key] = armory[key] + [False if key=="owned" else 0]*(len(NAMES)-len(armory[key]))
    if version < 3:
        pad_armory(armory,game.armory,8 if legacy else 11)
    restore_attributes(game.armory, armory, ARM_FIELDS)
    require(game.clock >= 0. and 0 < game.player.health <= 100 and 0 <= game.inventory_slot < len(ITEMS))
    require(valid_position(game.player.x, game.player.y))
    require(0 <= game.district < len(game.level.districts) and 0 <= game.kills <= game.total_kills
            and 0 <= game.secrets <= game.total_secrets)
    arm = game.armory
    require(0 <= arm.active < len(NAMES) and arm.owned[arm.active])
    require(all(0 <= a <= cap for a, cap in zip(arm.loaded, CAPACITY))
            and all(0 <= a <= cap for a, cap in zip(arm.reserve, MAX_RESERVE)))
    expanded = version < VERSION
    doors = [(w.door_ids[door.x,door.y],door) for door in w.doors
             if not expanded or (door.x,door.y) not in w.extension_doors]
    enemies = [(key,enemy) for key,enemy in zip(game.enemy_ids,game.enemies)
               if (not expanded or key not in w.extension_enemies)
               and (version!=2 or key not in w.v2_new_enemies)]
    for records, entities, keys in ((doc["doors"],doors,DOOR_FIELDS),
                                    (doc["enemies"],enemies,ENEMY_FIELDS)):
        if legacy:
            # Hickston keeps its v1 door and enemy ordering.
            require(isinstance(records, list) and len(records) == len(entities))
        else:
            require(isinstance(records,dict) and set(records)=={key for key,_ in entities})
            records = [records[key] for key,_ in entities]
        for (_,obj),row in zip(entities,records):
            if hasattr(obj, "kind"):
                require(isinstance(row,dict) and obj.kind == row.get("kind"))
            restore_attributes(obj, row, keys)
            if hasattr(obj, "progress"):
                require(0 <= obj.progress <= 1.)
            else:
                require(valid_position(obj.x,obj.y))
    reactions = doc.get("county_reactions",{})
    require(isinstance(reactions,dict) and set(reactions)<=set(game.enemy_ids))
    for key,enemy in zip(game.enemy_ids,game.enemies):
        if key not in reactions:
            continue
        row = reactions[key]
        require(isinstance(row,list) and len(row)==3 and type(row[2]) is bool)
        heard,retreat,enemy.responded = row
        for state,length in ((heard,4),(retreat,3)):
            if state is not None:
                require(isinstance(state,list) and len(state)==length and valid_position(*state[:2])
                        and all(numeric(t) and 0<=t<=game.clock+3. for t in state[2:]))
        require(heard is None or heard[2]<=heard[3])
        require(retreat is None or enemy.responded)
        enemy.heard = tuple(heard) if heard is not None else None
        enemy.retreat = tuple(retreat) if retreat is not None else None
    if legacy:
        # V1 never stored an aim point. Cancel the pending shot and allow a fresh telegraph.
        for enemy in game.enemies:
            if enemy.windup:
                enemy.windup = 0.
                enemy.cooldown = max(enemy.cooldown, .35)
    else:
        ai = doc["ai"]
        require(isinstance(ai, dict) and set(ai) == {key for key,_ in enemies})
        ai_fields = AI_FIELDS + COMBAT_FIELDS if version>=3 else AI_FIELDS
        for key, enemy in enemies:
            row = ai[key]
            require(isinstance(row, dict) and set(row) == {*ai_fields, "aim"})
            restore_attributes(enemy, {field: row[field] for field in ai_fields}, ai_fields)
            require(0 <= enemy.route_slot < max(1, len(enemy.route)))
            require(0<=enemy.volley<=5 and 0.<=enemy.pressure_guard<=1.75)
            aim = row["aim"]
            require(aim is None or isinstance(aim, list) and len(aim) == 3 and all(map(numeric, aim)))
            require(not enemy.windup or aim is not None)
            enemy.aim_mark = tuple(aim) if aim is not None else None
        data = doc["campaign"]
        require(isinstance(data, dict) and type(data.get("replay")) is bool)
        game.replay = data["replay"]
        if version==2:
            pad_armory(data["entry"],game.armory,11)
        game.entry = validate_kit(data["entry"])
        history = data["history"]
        previous = LEVELS[:LEVELS.index(game.level)] if not game.replay else ()
        require(isinstance(history, list) and len(history) == len(previous))
        for result, level in zip(history, previous):
            require(isinstance(result, list) and len(result) == 6 and result[0] == level.id
                    and all(type(n) is int and 0 <= n <= 1e7 for n in result[1:])
                    and result[1] <= result[2] and result[3] <= result[4])
        game.history = tuple(map(tuple, history))
        stations = doc["stations"]
        require(isinstance(stations, list) and all(isinstance(name,str) for name in stations))
        game.stations_done = set(stations)
        if version==2:
            for station,required in w.v2_implied_tasks.items():
                if station in game.stations_done:
                    game.stations_done.update(required)
        require(game.stations_done <= {station.id for station in w.stations})
        for station in w.stations:
            if station.id in game.stations_done:
                require(game.stations_done.issuperset(station.requires))
                game.set_station_lights(station)
        if w.extraction:
            if version==2 and game.finale and w.extraction.shutdown in game.stations_done:
                game.finale.dormant = False
                game.finale.cooldown = 2.5
                game.message("LOADING AREA THREAT. WATCH THE WARNING SIGNAL.",3.5)
            require(all(enemy.dormant == (w.extraction.shutdown not in game.stations_done)
                        for enemy in game.wave))
    require(expected_replay is None or game.replay == expected_replay)
    bookmark = doc.get("music") if version>=3 else None
    if bookmark is not None:
        tracks = SCORES[game.level.score]
        require(isinstance(bookmark,dict) and set(bookmark)=={"track","remaining","offset"}
                and bookmark["track"] in tracks and numeric(bookmark["offset"])
                and 0<=bookmark["offset"]<=600 and isinstance(bookmark["remaining"],list)
                and all(isinstance(track,str) and track in tracks and track!=bookmark["track"]
                        for track in bookmark["remaining"])
                and len(set(bookmark["remaining"]))==len(bookmark["remaining"]))
    game.music_bookmark=bookmark
    game.shots = restore_list(doc["shots"], Shot, SHOT_KINDS, 240)
    game.specks = restore_list(doc["specks"], Speck, SPECK_KINDS, 4000)
    game.blasts = restore_list(doc["blasts"], Blast, {"energy","fire"}, 80)
    game.hazards = restore_list(doc["hazards"],Hazard,{"steam","chalk"},7) if version>=3 else []
    require(all(valid_position(h.x,h.y) and 0<h.radius<=1.05 and 0<=h.warning<h.life<=2.8
                and 0<=h.age<h.life and 0<=h.damage<=20 for h in game.hazards))
    for records in (game.shots, game.specks, game.blasts):
        require(all(valid_position(obj.x,obj.y) for obj in records))
    inv = doc["inventory"]
    if isinstance(inv,dict):
        for name in ITEMS:
            inv.setdefault(name,0)
    require(isinstance(inv,dict) and set(inv) == set(ITEMS)
            and all(type(n) is int and 0 <= n <= 5 for n in inv.values()))
    game.inventory = inv
    require(isinstance(doc["keys"],list) and set(doc["keys"]) <= {"key_brass","key_steel"})
    game.keys = set(doc["keys"])
    require(isinstance(doc["drums"],list) and all(
        isinstance(row,list) and len(row)==3 and tuple(row[:2]) in w.fuel_drums and 0 < row[2] <= 18
        for row in doc["drums"]))
    game.drums = {(x,y): hp for x,y,hp in doc["drums"]}
    require(isinstance(doc["pickups"], list) and all(
        isinstance(row,list) and len(row)==3 and row[0] in (*PICKUP_NAMES,*AMMO,*NAMES)
        and valid_position(*row[1:]) for row in doc["pickups"]))
    game.pickups = [tuple(row) for row in doc["pickups"]]
    if not expanded:
        items,turns,spent = doc.get("tasks",[]),doc.get("valve_turns",{}),doc.get("scenery",[])
        crank_ids = {station.id for station in w.stations if station.action=="crank"}
        props = {prop.id:prop for prop in w.scenery}
        require(type(items) is list and all(type(name) is str and name in TASK_ITEMS for name in items))
        require(type(turns) is dict and set(turns) <= crank_ids and not set(turns) & game.stations_done
                and all(type(count) is int and 0<count<3 for count in turns.values()))
        require(type(spent) is list and all(type(key) is str and key in props for key in spent))
        game.task_items,game.valve_turns,game.scenery_spent = set(items),turns,set(spent)
        heard = doc.get("heard", [])
        require(type(heard) is list and all(type(key) is str and
                key in {exchange.id for exchange in game.exchanges} for key in heard))
        game.heard_exchanges = set(heard)
        opened = {(door.x,door.y) for door in w.doors if door.opened}
        require(all(set(props[key].opens)<=opened and
                    (not props[key].station or props[key].station in game.stations_done)
                    for key in spent))
    if expanded:
        game.legacy_completed = game.won
        game.legacy_key_route = any(name=="key_steel" for name,_,_ in game.pickups) and game.level.rescue
        if game.level.id=="fair" and "games" in game.stations_done:
            game.task_items.add("pa_patch")
        if not game.won:
            game.pickups.extend(item for item in w.extension_pickups
                                if item[0]!="key_steel" and item[0] not in game.task_items)
        opened = {point for station in w.stations if station.id in game.stations_done for point in station.opens}
        for door in w.doors:
            if (door.x,door.y) in w.extension_doors and (door.x,door.y) in opened:
                door.opened,door.progress = True,1.
    if game.legacy_completed:
        require(game.won)
        added = [enemy for key,enemy in zip(game.enemy_ids,game.enemies) if key in w.extension_enemies]
        for enemy in added:
            enemy.dormant = True
        game.total_kills -= sum(enemy.hostile for enemy in added)
        require(game.kills<=game.total_kills)
    require(isinstance(doc["visited"],list) and all(
        isinstance(row,list) and len(row)==2 and valid_position(*row) and all(type(n) is int for n in row)
        for row in doc["visited"]))
    game.visited = {tuple(row) for row in doc["visited"]}
    require(isinstance(doc["panes"],list) and all(
        isinstance(row,list) and len(row)==2 and tuple(row) in w.pane_tiles for row in doc["panes"]))
    w.broken_panes = {tuple(row) for row in doc["panes"]}
    state = doc["rng"]
    require(isinstance(state,list) and len(state)==3 and isinstance(state[1],list)
            and len(state[1])==625 and all(type(n) is int for n in state[1]))
    game.rng.setstate((state[0],tuple(state[1]),state[2]))
    if version < VERSION:
        # The new layout may have a solid prop where a legacy actor was saved.
        p=game.player
        x,y=clear_legacy_position(w,p.x,p.y,p.angle,PLAYER_RADIUS,game.level.spawn[:2])
        if (x,y)!=(p.x,p.y):
            p.eye += w.elevation(x,y)-w.elevation(p.x,p.y)
            p.x,p.y,p.vx,p.vy=x,y,0.,0.
        homes={key:(x,y) for key,(_,x,y) in zip(w.enemy_ids,w.enemies)}
        for key,enemy in enemies:
            if enemy.alive:
                enemy.x,enemy.y=clear_legacy_position(w,enemy.x,enemy.y,enemy.angle,enemy.radius,homes[key])
    return game

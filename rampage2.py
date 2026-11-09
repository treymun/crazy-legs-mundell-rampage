"""2.0 additions: player one-liners, drunk screen warp, Hick Mode cheat codes."""
import math
import random

import numpy as np
import pygame as pg

# ---------------------------------------------------------------- one-liners
LINES = {
    "kill": (
        "THAT'S ONE LESS VARMINT.", "YEE-HAW!", "BACK TO THE DIRT, SON.", "DON'T MESS WITH THE LEGS.",
        "SHOULD'VE STAYED HOME.", "THAT'LL LEARN YA.", "SOMEBODY CALL THE UNDERTAKER.",
        "FIXIN' TO BE FERTILIZER.", "BLESS YOUR HEART.", "HOLD MY BEER.",
        "NOT IN MY COUNTY.", "THAT'S GONNA LEAVE A MARK.",
    ),
    "streak": (
        "WHO'S NEXT?", "I'M JUST GETTIN' WARMED UP.", "RAMPAGE TIME!", "LINE UP, BOYS.",
    ),
    "pickup_weapon": (
        "NOW WE'RE TALKIN'.", "COME TO PAPPY.", "THAT'LL DO NICELY.", "HOT DIGGITY.",
        "OH, YOU PURTY THING.",
    ),
    "pickup_food": (
        "GOOD EATIN'.", "MMM, SALTY.", "THAT HITS THE SPOT.", "WASH IT DOWN.",
    ),
    "hurt": (
        "OW! THAT STUNG.", "WHY, I OUGHTA...", "YOU'LL PAY FER THAT.", "RIGHT IN THE OVERALLS!",
    ),
    "low": (
        "I'M SEEIN' THE LIGHT...", "NEED ME A SNACK.", "TOO MEAN TO DIE.", "SOMEBODY GET MAMA.",
    ),
    "reload": (
        "LOCK AND LOAD.", "ANOTHER ROUND.", "COME ON, COME ON...", "FEED THE BEAST.",
    ),
    "empty": (
        "CLICK. WELL, SHUCKS.", "OUT OF SHELLS!",
    ),
    "drunk": (
        "HIC! WHO MOVED THE BARN?", "THE GROUND'S MOVIN'.", "I SEE TWO OF YA.",
    ),
    "secret": (
        "WELL, LOOKY HERE.", "NOW THAT'S A SECRET.",
    ),
}
COOLDOWN = {"kill": 6.0, "streak": 8., "pickup_weapon": 4., "pickup_food": 7., "hurt": 7.5,
            "low": 14., "reload": 12., "empty": 6., "drunk": 20., "secret": 4.}
GLOBAL_GAP = 2.6
SHOW_FOR = 2.2


class Barks:
    """Short player one-liners with per-category cooldowns and no immediate repeats."""

    def __init__(self, seed=1997):
        self.rng = random.Random(seed)
        self.last_at = {}
        self.last_line = {}
        self.next_any = 0.
        self.text = ""
        self.until = 0.
        self.recent_kills = []
        self.enabled = True

    def say(self, game, category, force=False):
        if not self.enabled:
            return False
        now = game.clock
        if not force and (now < self.next_any or now - self.last_at.get(category, -99.) < COOLDOWN[category]):
            return False
        pool = LINES[category]
        choices = [line for line in pool if line != self.last_line.get(category)] or pool
        line = self.rng.choice(choices)
        self.last_line[category] = line
        self.last_at[category] = now
        self.next_any = now + GLOBAL_GAP
        self.text, self.until = line, now + SHOW_FOR
        if category in ("kill", "streak") and self.rng.random() < .35:
            game.sound.play("yee_haw_alt" if self.rng.random() < .5 else "yee_haw", .7)
        return True

    def kill(self, game):
        self.recent_kills = [t for t in self.recent_kills if game.clock - t < 7.] + [game.clock]
        if len(self.recent_kills) >= 3:
            if self.say(game, "streak"):
                self.recent_kills.clear()
                return
        self.say(game, "kill")

    def visible(self, game):
        return self.enabled and self.until > game.clock


# ----------------------------------------------------------------- drunk warp
def drunk_warp(scene, drunk, clock):
    """Wobble and double vision driven by the DRUNK meter (0-100). Cheap numpy shear."""
    if drunk < 38:
        return
    strength = min(1., (drunk - 38) / 62)
    pixels = pg.surfarray.pixels3d(scene)
    width, height = pixels.shape[:2]
    rows = np.arange(height)
    shift = np.rint(np.sin(rows * .16 + clock * 3.1) * (1 + 3.4 * strength)).astype(np.int32)
    cols = (np.arange(width)[:, None] + shift[None, :]) % width
    source = pixels[cols, rows[None, :]].astype(np.uint16)
    ghost_dx = int(2 + 4 * strength)
    ghost = np.roll(source, ghost_dx * (1 if math.sin(clock * 1.7) > 0 else -1), axis=0)
    mix = .30 * strength
    out = source * (1 - mix) + ghost * mix
    # Warm amber tint, like looking through a jar.
    out[..., 0] *= 1 + .06 * strength
    out[..., 2] *= 1 - .10 * strength
    pixels[:] = np.clip(out, 0, 255).astype(np.uint8)
    del pixels


# --------------------------------------------------------------- Hick Mode
CODES = {
    "hickgod": "HICK MODE: TOO MEAN TO DIE",
    "hickguns": "HICK MODE: ALL THE GUNS",
    "hickhp": "HICK MODE: FULL TANK",
    "hickbooze": "HICK MODE: STOCKED CELLAR",
    "hickbarks": "HICK MODE: BIG MOUTH",
}


class Cheats:
    def __init__(self):
        self.buffer = ""
        self.god = False
        self.used = False

    def feed(self, key, game):
        """Feed a pygame key; returns the confirmation text when a code completes."""
        name = pg.key.name(key)
        if len(name) != 1 or not name.isalpha():
            return None
        self.buffer = (self.buffer + name)[-10:]
        for code, text in CODES.items():
            if self.buffer.endswith(code):
                self.buffer = ""
                self.apply(code, game)
                self.used = True
                return text + (" (ON)" if code == "hickgod" and self.god else
                               " (OFF)" if code == "hickgod" else "")
        return None

    def apply(self, code, game):
        from weapons import MAX_RESERVE, NAMES
        p = game.player
        if code == "hickgod":
            self.god = not self.god
        elif code == "hickhp":
            p.health = 100
        elif code == "hickguns":
            a = game.armory
            for i in range(len(NAMES)):
                a.owned[i] = True
                a.reserve[i] = MAX_RESERVE[i]
        elif code == "hickbooze":
            for key in game.inventory:
                game.inventory[key] = 5
        elif code == "hickbarks":
            game.barks_off_by_code = game.barks.enabled
            game.barks.enabled = not game.barks.enabled


# ---- 2.0 look pass: per-chapter wash, flicker, ordered dither, grit ----
_BAYER = None
_GRIT = {}
GRAIN_FRAMES = 6
WASH = {"hickston": (255, 226, 190, .10), "fair": (255, 200, 230, .12),
        "sawmill": (255, 214, 160, .13), "quarry": (178, 214, 255, .12)}


def _grit_tables(w, h):
    """Cached vignette and animated grain sized to the scene view."""
    key = (w, h)
    if key not in _GRIT:
        import numpy as np
        # surfarray pixels are (width, height), so build tables in that order.
        xx, yy = np.mgrid[0:w, 0:h].astype(np.float32)
        # Normalised radius pushes corners down ~13% for a dirty lens vignette.
        nx = (xx / max(w - 1, 1) - .5) * 2.
        ny = (yy / max(h - 1, 1) - .5) * 2.
        radius = np.sqrt(nx * nx + ny * ny) / 1.4142
        _GRIT[key] = (1. - .13 * radius ** 2.1)[..., None]
        rng = np.random.default_rng(11 + w * 7 + h)
        # Pre-baked film grain avoids per-frame RNG cost; frames cycle on time.
        _GRIT[(w, h, "grain")] = [
            rng.integers(-2, 3, (w, h, 1), dtype=np.int16).astype(np.float32)
            for _ in range(GRAIN_FRAMES)]
    return _GRIT[key], _GRIT[(w, h, "grain")]


def look_pass(view, level_id, clock, indoors, flicker, blast):
    import numpy as np
    import pygame as pg
    global _BAYER
    if _BAYER is None:
        b = np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]], dtype=np.float32)
        _BAYER = (b / 16. - .5)
    px = pg.surfarray.pixels3d(view)
    w, h = px.shape[:2]
    vignette, grain = _grit_tables(w, h)
    r, g, b, a = WASH.get(level_id, (255, 255, 255, 0))
    tint = np.array((r, g, b), dtype=np.float32) / 255.
    amount = a
    gain = 1.
    if indoors and flicker:
        # lamps buzz and occasionally stutter
        buzz = .985 + .015 * np.sin(clock * 53.) + (-.07 if (int(clock * 7.3) % 29 == 0 and (clock * 7.3) % 1 < .35) else 0.)
        gain = buzz
    frame = px.astype(np.float32)
    frame *= (1. - amount) + tint * amount
    frame *= gain
    frame *= vignette
    frame += grain[int(clock * 17.) % GRAIN_FRAMES]
    if blast > 0.:
        frame += blast * 60.
    # ordered dither: +/-3 levels, quantised in 4x4 cells (screen space, stable)
    pattern = np.tile(_BAYER, (w // 4 + 1, h // 4 + 1))[:w, :h]
    frame += pattern[..., None] * 6.
    px[:] = np.clip(frame, 0, 255).astype(np.uint8)
    del px

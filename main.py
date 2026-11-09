"""Entry point for desktop, Android and Pygbag builds of Hickston."""
import argparse
import asyncio
import math
import os
from datetime import datetime
from pathlib import Path

import pygame as pg

from audio import Sound
from campaign import BY_ID, LEVELS, next_level
from engine import ASSETS, HEIGHT, WIDTH, Art
from game import Controls, Game
from game_version import VERSION
from hud import AMBER, HUD, INK, TITLE_FIRST, title_row_height
from period_palette import VGAPalette
from pixel_type import wrap
from resource_path import IS_ANDROID
import session_store
from touch_controls import TouchControls
from weapons import BOWLING, CAPACITY, COW, KEG, RIFLE, ROCKET, SHOTGUN, TEAT
from hud import ITEMS

TITLE = "Crazy Legs Mundell Rampage | The Hickston Incident"
SIM_STEP = 1/120
SETUP_X, SETUP_Y, SETUP_ROW = 23, 56, 12
SETUP_TAB = 276 // len(session_store.SETUP_PAGES)
REPLAY_TOP, REPLAY_ROW = 46, 25
SLOT_TOP, SLOT_ROW = 51, 25
CONTROL_ROWS = (
    ("WASD / MOUSE", "MOVE / AIM"),
    ("SHIFT / J / Z", "RUN / JUMP / CROUCH"),
    ("MOUSE 1 / 2", "FIRE / WEAPON ALT FIRE"),
    ("1-9  0  -  =", "WEAPONS / WHEEL / R LOAD"),
    ("8 + HOLD FIRE", "LIGHT TNT / RELEASE THROW"),
    ("Q / F", "SELECT ITEM / USE ITEM"),
    ("C / B / M", "RINDS / BEER / MOONSHINE"),
    ("E / SPACE / MMB", "USE / OPEN / RESCUE"),
    ("TAB / F4 / F11", "MAP / MUSIC / FULLSCREEN"),
    ("F5 / F6 / F9", "SLOTS / QUICKSAVE / QUICKLOAD"),
)


class Desktop:
    def __init__(self, smoke=False, profile=None):
        self.focused = True
        pg.mixer.pre_init(22050, -16, 2, 512)
        pg.init()
        pg.display.set_caption(TITLE)
        self.fullscreen = False
        self.fullscreen_mode = 1
        if IS_ANDROID and not smoke:
            try:
                self.screen = pg.display.set_mode((0, 0), pg.SCALED | pg.FULLSCREEN)
            except pg.error:
                self.screen = pg.display.set_mode((960, 540), pg.FULLSCREEN)
            self.fullscreen = True
            self.fullscreen_mode = 1
        else:
            self.screen = pg.display.set_mode((640, 480) if smoke else (960, 720), pg.RESIZABLE)
        self.window_size = self.screen.get_size()
        try:
            pg.display.set_icon(pg.image.load(ASSETS / "art" / "hickston_icon.png"))
        except pg.error:
            pass
        self.touch = TouchControls()
        self.touch.layout(self.screen.get_size())
        self.canvas = pg.Surface((WIDTH, HEIGHT)).convert()
        self.palette = VGAPalette()
        self.clock = pg.time.Clock()
        self.art = Art()
        self.hud = HUD(self.art)
        self.sound = Sound()
        self.game = None
        self.campaign_run = None
        self.hub_origin = None
        self.replay_runs = {}
        self.state = "title"
        self.selection = 0
        self.running = True
        self.smoke = smoke
        self.profile = profile if profile is not None else None if smoke else session_store.data_directory()
        self.save_path = self.profile / session_store.SLOT if self.profile else None
        self.settings_path = self.profile / session_store.SETTINGS_FILE if self.profile else None
        self.unlocks_path = self.profile / session_store.UNLOCKS_FILE if self.profile else None
        self.entry_path = self.profile / session_store.ENTRY_FILE if self.profile else None
        self.notes_path = self.profile / session_store.ROAD_NOTES_FILE if self.profile else None
        self.hub_findings = session_store.road_notes(self.notes_path)
        self.hub_visited = set()
        self.unlocked = session_store.unlocks(self.unlocks_path)
        self.replay_selection = 0
        self.options = session_store.settings(self.settings_path)
        self.option_slot = 0
        self.option_page = 0
        self.menu_note = ""
        self.block_fire = False
        self.crouch_latched = False
        self.accumulator = self.pending_turn = self.pending_look = 0.
        self.focus_grace = 0
        self.pad = None
        self.pad_down = {}
        self.apply_options()
        if self.options["window_mode"] and not smoke and not IS_ANDROID:
            self.change_window_mode(self.options["window_mode"])

    @property
    def entries(self):
        entries = ("NEW GAME", "COUNTY HUB", "REPLAY LEVEL", "SAVE SLOTS", "SETUP", "CONTROLS", "CREDITS", "QUIT")
        if self.save_path and self.save_path.is_file():
            entries = (entries[0],"QUICKLOAD",*entries[1:])
        if self.game:
            return ("RESUME", *entries)
        if self.campaign_run or self.entry_path and self.entry_path.is_file():
            return ("CONTINUE CAMPAIGN", *entries)
        return entries

    def grab(self, value):
        pg.event.set_grab(value and not self.smoke)
        pg.mouse.set_visible(not value or self.smoke)
        pg.mouse.get_rel()
        self.accumulator = self.pending_turn = self.pending_look = 0.

    def start(self, level_id="hickston", *, kit=None, history=(), replay=False, supply_rule=None):
        self.menu_note = ""
        game = self.make_game(level_id)
        game.supply_rule = self.options["supply_rule"] if supply_rule is None else supply_rule
        game.replay = replay
        game.history = history
        if replay and kit is None and level_id != "hickston":
            game.armory.owned[SHOTGUN] = game.armory.owned[RIFLE] = True
            game.armory.loaded[SHOTGUN], game.armory.loaded[RIFLE] = CAPACITY[SHOTGUN], CAPACITY[RIFLE]
            game.armory.reserve[SHOTGUN], game.armory.reserve[RIFLE] = 16, 48
            game.armory.active = SHOTGUN
            game.inventory["rinds"] = 2
            new_weapon,spares = {"fair":(ROCKET,3),"sawmill":(BOWLING,3),"quarry":(COW,3)}[level_id]
            game.armory.owned[new_weapon] = True
            game.armory.loaded[new_weapon] = CAPACITY[new_weapon]
            game.armory.reserve[new_weapon] = spares
            for extra,spare in ((TEAT,60),(KEG,2)):
                game.armory.owned[extra] = True
                game.armory.loaded[extra] = CAPACITY[extra]
                game.armory.reserve[extra] = spare
        if kit is not None:
            game.apply_loadout(kit)
        game.entry = game.loadout()
        self.play(game)

    def make_game(self, level_id="hickston"):
        return Game(self.art, self.hud, self.sound, level_id)

    def play(self, game):
        self.game = game
        if not game.replay and not game.in_hub and not game.revisiting:
            self.campaign_run = game
        if game.replay:
            self.replay_runs[game.level.id] = game
        game.configure(self.options)
        self.crouch_latched = bool(game.player.crouched and self.options["crouch"])
        self.sound.pause_world()
        self.sound.set_score("victory" if game.showing_tally else "title" if game.in_hub else game.level.score)
        self.sound.pause_score(False)
        self.state = "play"
        self.block_fire = True
        self.grab(not game.showing_tally and game.player.health>0)

    def open_hub(self, origin=None, message=None):
        if origin and not origin.in_hub:
            self.hub_origin = origin
            if not origin.replay and self.campaign_run and self.entry_path:
                try:
                    self.write_campaign(self.campaign_run,self.entry_path)
                except (OSError,ValueError,TypeError):
                    message = "CROSSROADS OPEN. PROGRESS COULD NOT BE SAVED."
        hub = self.make_game()
        hub.in_hub = True
        hub.hub_findings = self.hub_findings
        hub.visited = self.hub_visited
        hub.world.locked_gates = tuple(gate for gate in hub.world.hub_gates
                                       if gate.destination not in self.unlocked)
        for gate in hub.world.hub_gates:
            level_id = gate.destination
            if self.hub_origin and self.hub_origin.replay and self.hub_origin.level.id == level_id:
                hub.gate_modes[level_id] = "RESUME REPLAY"
            elif self.campaign_run and self.campaign_run.level.id == level_id:
                hub.gate_modes[level_id] = "REVISIT" if self.campaign_run.won else "CONTINUE"
            elif self.campaign_run and level_id in self.campaign_run.retained:
                hub.gate_modes[level_id] = "REVISIT"
            elif level_id in self.replay_runs:
                hub.gate_modes[level_id] = "RESUME REPLAY"
            elif self.campaign_run or level_id != "hickston":
                hub.gate_modes[level_id] = "REPLAY"
        carried = self.campaign_run or self.hub_origin
        if self.campaign_run:
            hub.hub_milestone = len(self.campaign_run.history)+int(self.campaign_run.won)
        if carried and carried.player.health > 0:
            hub.apply_loadout(carried.loadout())
        hub.player.x, hub.player.y, hub.player.angle = 24.5, 53.90, -math.pi/2
        hub.district = 11
        hub.message(message or "COUNTY CROSSROADS. FACE A GATE AND PRESS E.", 4.5)
        self.play(hub)

    def travel(self, destination):
        current = self.game
        current.portal_request = None
        if destination == "hub":
            self.open_hub(current)
        elif destination in self.unlocked:
            campaign = self.campaign_run
            origin = self.hub_origin
            chapter = None
            if campaign:
                chapter = campaign if campaign.level.id == destination else campaign.retained.get(destination)
            if origin and origin.replay and origin.level.id==destination and not origin.won:
                self.face_into_level(origin)
                self.play(origin)
            elif chapter:
                chapter.revisiting = chapter.won
                self.face_into_level(chapter)
                self.play(chapter)
            elif destination in self.replay_runs:
                replay=self.replay_runs[destination]
                self.face_into_level(replay)
                self.play(replay)
            else:
                self.start(destination, replay=bool(campaign) or destination != "hickston")

    def face_into_level(self,game):
        p,gate = game.player,game.world.return_gate
        if gate and abs(p.x-gate.x)<gate.width*.5 and abs(p.y-gate.y)<3.0:
            if (p.y-gate.y)*gate.side < -.30:
                x,y = gate.x,gate.y+gate.side*1.65
                p.eye += game.world.elevation(x,y)-game.world.elevation(p.x,p.y)
                p.x,p.y = x,y
            p.angle,p.pitch,p.vx,p.vy = gate.side*math.pi/2,0.,0.,0.

    def bookmark_campaign_audio(self,game):
        for chapter in (game,*game.retained.values()):
            bookmark=self.sound.bookmark_score(chapter.level.score)
            if bookmark is not None:
                chapter.music_bookmark=bookmark

    def write_campaign(self,game,path):
        self.bookmark_campaign_audio(game)
        session_store.save(game,path)

    def restore_campaign_audio(self,game):
        for chapter in (game,*game.retained.values()):
            self.sound.restore_score(chapter.level.score,chapter.music_bookmark)

    def resume_entry(self):
        if self.campaign_run:
            self.open_hub(self.campaign_run, "CAMPAIGN READY. USE YOUR CURRENT GATE.")
            return
        try:
            game = session_store.read(self.entry_path, self.make_game, migrate=True, expected_replay=False)
        except (OSError, ValueError, KeyError, TypeError, OverflowError, RecursionError):
            self.notice("THE CAMPAIGN ENTRY COULD NOT BE LOADED.")
            return
        self.campaign_run = game
        self.restore_campaign_audio(game)
        self.unlocked.update(level.id for level in LEVELS[:LEVELS.index(game.level)+1])
        self.open_hub(game, "CAMPAIGN READY. USE YOUR NEXT GATE.")

    def continue_campaign(self):
        game = self.game
        following = next_level(game.level.id)
        if game.replay:
            self.replay_runs.pop(game.level.id,None)
            if self.hub_origin is game:
                self.hub_origin=None
            self.return_to_title(discard=True)
            return
        if following is None:
            self.open_hub(game,"SHIFT COMPLETE. OPEN ROADS LEAD BACK TO FINISHED CHAPTERS.")
            return
        self.start(following.id,kit=game.loadout(),history=(*game.history,game.result()),
                   supply_rule=game.supply_rule)
        self.game.retained = {**game.retained,game.level.id:game}
        self.unlocked.add(following.id)
        message = "GATE OPEN: " + following.title
        if self.unlocks_path:
            try:
                # Merge with a profile another game instance may have advanced.
                self.unlocked |= session_store.unlocks(self.unlocks_path)
                session_store.save_unlocks(self.unlocks_path, self.unlocked)
            except OSError:
                message = "GATE OPEN. UNLOCK COULD NOT BE SAVED."
        if self.options.get("classic", 0):
            self.notice(message, 1.8)
            return
        self.open_hub(self.game, message)

    def return_to_title(self, discard=False):
        if discard:
            self.game = None
            self.sound.set_score("title")
        self.sound.pause_score(not discard)
        self.state = "title"
        self.selection = 0
        self.sound.pause_world()
        self.grab(False)

    def menu_action(self):
        entries = self.entries
        entry = entries[self.selection % len(entries)]
        self.menu_note = ""
        if entry == "RESUME":
            self.state = "play"
            self.sound.pause_score(False)
            self.grab(not self.game.showing_tally and self.game.player.health > 0)
        elif entry == "NEW GAME":
            self.start()
            if self.entry_path:
                try:
                    session_store.save(self.game,self.entry_path)
                except OSError:
                    self.notice("CAMPAIGN ENTRY COULD NOT BE SAVED.")
        elif entry == "CONTINUE CAMPAIGN":
            self.resume_entry()
        elif entry == "COUNTY HUB":
            if self.game and self.game.armory.fuse:
                self.notice("THROW THE LIT STICK BEFORE LEAVING.")
            else:
                self.open_hub(self.game)
        elif entry == "QUICKLOAD":
            self.load_game()
        elif entry == "REPLAY LEVEL":
            self.replay_selection = 0
            self.state = "replays"
        elif entry == "SAVE SLOTS":
            self.show_slots("load")
        elif entry in ("CONTROLS", "CREDITS","SETUP"):
            self.state = entry.lower()
        else:
            self.running = False

    def notice(self, text, duration=2.1):
        if self.state == "play" and self.game and self.game.player.health > 0:
            self.game.message(text,duration)
        else:
            self.menu_note = text

    def current_slot(self):
        if self.profile and self.state == "play" and self.game and self.game.replay:
            return self.profile / f"replay-{self.game.level.id}-quick.json"
        return self.save_path

    def save_game(self):
        g = self.game
        slot = self.current_slot()
        if g and g.in_hub:
            self.notice("ENTER A LEVEL TO QUICKSAVE.")
        elif not slot or self.state != "play" or not g or g.player.health <= 0 or g.showing_tally:
            self.notice("START A LIVE RUN TO SAVE.")
        elif g.armory.fuse:
            self.notice("THROW THE LIT STICK BEFORE SAVING.")
        else:
            try:
                self.write_campaign(self.campaign_run if g.revisiting else g,slot)
            except (OSError,ValueError,TypeError):
                self.notice("COULD NOT WRITE THE QUICKSAVE.")
            else:
                self.notice("CAMPAIGN SAVED. USE THE HUB TO REVISIT." if g.revisiting else "GAME SAVED. F9 TO LOAD.")
                self.sound.play("menu_accept",.65)

    def load_game(self):
        slot = self.current_slot()
        if not slot or not slot.is_file():
            self.notice("NO QUICKSAVE YET.")
            return
        replay = slot != self.save_path
        self.load_checkpoint(slot,replay,self.game.level.id if replay and self.game else None)

    def load_checkpoint(self, slot, replay, level=None, notice="QUICKSAVE LOADED."):
        try:
            g = session_store.read(slot,self.make_game,migrate=True,expected_replay=replay,expected_level=level)
        except (OSError,ValueError,KeyError,TypeError,OverflowError,RecursionError):
            self.notice("COULD NOT LOAD THAT SAVE. FILE PRESERVED.")
            return
        self.restore_campaign_audio(g)
        self.play(g)
        if not g.replay:
            self.unlocked.update(level.id for level in LEVELS[:LEVELS.index(g.level)+1])
        self.notice(notice)
        self.sound.play("menu_accept",.65)

    def show_slots(self, mode):
        if not self.profile:
            self.notice("NO SAVE PROFILE AVAILABLE.")
            return
        self.slots_return = self.state
        self.slot_replay = self.game.level.id if self.game and self.game.replay else None
        self.slot_mode = mode
        self.slot_index = 0
        self.slot_stage = "choose"
        self.slot_name = ""
        self.menu_note = ""
        self.state = "slots"
        self.sound.pause_world()
        self.sound.pause_score(True)
        self.grab(False)
        self.refresh_slots()

    def refresh_slots(self):
        root = session_store.slot_directory(self.profile,self.slot_replay)
        self.slots = [(path,*session_store.slot_metadata(path,self.slot_replay))
                      for path in (root/f"slot-{i+1}.json" for i in range(session_store.MANUAL_SLOTS))]

    def slot_source(self):
        g = self.game
        if not g or g.in_hub or g.showing_tally or g.player.health <= 0 or g.armory.fuse:
            return None
        return self.campaign_run if g.revisiting else g

    def slot_commit(self):
        game = self.slot_source()
        if not game:
            self.menu_note = "A LIVE LEVEL WITHOUT A LIT FUSE IS REQUIRED."
            return
        path,digest,meta = self.slots[self.slot_index]
        name = self.slot_name.strip() or (meta[0] if meta else f"SLOT {self.slot_index+1}")
        try:
            self.bookmark_campaign_audio(game)
            session_store.save_named(game,path,name,digest)
        except (OSError,ValueError,TypeError):
            self.menu_note = "SAVE FAILED OR SLOT CHANGED. FILE PRESERVED."
        else:
            self.menu_note = f"SAVED {name}."
            self.sound.play("menu_accept")
        self.slot_stage = "choose"
        self.refresh_slots()

    def key_slots(self, key):
        if self.slot_stage == "edit":
            if key==pg.K_BACKSPACE:
                self.slot_name = self.slot_name[:-1]
            elif key in (pg.K_ESCAPE,pg.K_RETURN):
                pg.key.stop_text_input()
                self.slot_stage = "choose"
                if key==pg.K_RETURN:
                    if self.slots[self.slot_index][2]:
                        self.slot_stage = "overwrite"
                    else:
                        self.slot_commit()
            return
        if self.slot_stage == "overwrite":
            if key==pg.K_RETURN:
                self.slot_commit()
            elif key==pg.K_ESCAPE:
                self.slot_stage = "choose"
            return
        if key==pg.K_ESCAPE:
            self.state = self.slots_return
            self.menu_note = ""
            self.sound.pause_score(self.state=="title" and self.game is not None)
            if self.state=="play":
                self.block_fire = True
                self.grab(self.game.player.health>0 and not self.game.showing_tally)
        elif key in (pg.K_TAB,pg.K_LEFT,pg.K_RIGHT):
            self.slot_mode = "save" if self.slot_mode=="load" else "load"
            self.menu_note = ""
        elif key in (pg.K_UP,pg.K_DOWN):
            self.slot_index = (self.slot_index + (1 if key==pg.K_DOWN else -1))%len(self.slots)
            self.menu_note = ""
        elif key==pg.K_RETURN:
            path,digest,meta = self.slots[self.slot_index]
            if digest=="":
                self.menu_note = "UNREADABLE OR INCOMPATIBLE SLOT. FILE PRESERVED."
            elif self.slot_mode=="load":
                if meta:
                    self.load_checkpoint(path,bool(self.slot_replay),self.slot_replay,"NAMED SAVE LOADED.")
                else:
                    self.menu_note = "THAT SLOT IS EMPTY."
            elif self.slot_source():
                self.slot_name = ""
                self.slot_stage = "edit"
                self.menu_note = ""
                pg.key.start_text_input()
            else:
                self.menu_note = "A LIVE LEVEL WITHOUT A LIT FUSE IS REQUIRED."

    @property
    def option_items(self):
        return session_store.SETUP_PAGES[self.option_page][1]

    def apply_options(self):
        opts = self.options
        self.sound.set_levels(opts["effects"]/100,opts["music"]/100,opts["ambience"]/100,opts["stereo"])
        self.sound.footstep_gain = opts["footsteps"]/100
        self.sound.voice_gain = opts["voice_volume"]/100
        self.palette.brightness(opts["brightness"])
        if self.game:
            self.game.configure(opts)

    def persist_options(self):
        if self.settings_path:
            try:
                session_store.save_settings(self.settings_path,self.options)
            except (OSError,ValueError):
                self.menu_note = "SETUP COULD NOT BE SAVED."

    def adjust_setting(self,direction):
        item = self.option_items[self.option_slot]
        self.options[item.key] = item.adjust(self.options[item.key],direction)
        if item.key == "crouch":
            self.crouch_latched = False
        if item.key == "window_mode":
            self.change_window_mode(self.options["window_mode"])
        self.apply_options()
        self.sound.play("menu_move")
        self.persist_options()

    def toggle_fullscreen(self):
        mode = 0 if self.fullscreen else self.fullscreen_mode
        self.change_window_mode(mode)
        self.options["window_mode"] = mode
        self.persist_options()

    def change_window_mode(self, mode):
        if not self.fullscreen:
            self.window_size = self.screen.get_size()
        self.fullscreen = bool(mode)
        if mode:
            self.fullscreen_mode = mode
        self.focus_grace = pg.time.get_ticks()+380
        if mode and IS_ANDROID:
            try:
                self.screen = pg.display.set_mode((0, 0), pg.SCALED | pg.FULLSCREEN)
            except pg.error:
                self.screen = pg.display.set_mode((0, 0), pg.FULLSCREEN)
        elif mode:
            self.screen = pg.display.set_mode((0,0),pg.FULLSCREEN)
        else:
            self.screen = pg.display.set_mode(self.window_size,pg.RESIZABLE)
        self.touch.layout(self.screen.get_size())
        self.grab(self.state == "play" and not self.game.showing_tally and self.game.player.health>0)

    def key(self, key):
        if self.state=="slots":
            self.key_slots(key)
            return
        if key == pg.K_F11:
            self.toggle_fullscreen()
            return
        if key == pg.K_F4:
            self.sound.toggle_music()
            return
        if key == pg.K_F5 and self.state in ("play","title"):
            self.show_slots("save" if self.slot_source() else "load")
            return
        if key in (pg.K_F2,pg.K_F6):
            self.save_game()
            return
        if key in (pg.K_F3,pg.K_F9):
            self.load_game()
            return
        if key == pg.K_F12 and self.profile:
            try:
                directory = self.profile / "screenshots"
                directory.mkdir(parents=True,exist_ok=True)
                filename = datetime.now().strftime("Hickston-%Y%m%d-%H%M%S-%f.png")
                pg.image.save(self.canvas,directory / filename)
                self.notice("SCREENSHOT SAVED.")
            except (OSError,pg.error):
                self.notice("COULD NOT SAVE THE SCREENSHOT.")
            return
        if self.state == "title" and self.game and self.game.player.health > 0:
            said = self.game.cheats.feed(key, self.game)
            if said:
                self.menu_note = said
                self.sound.play("yee_haw")
        if self.state == "setup":
            if key in (pg.K_UP,pg.K_DOWN):
                self.option_slot = (self.option_slot+(1 if key==pg.K_DOWN else -1))%len(self.option_items)
                self.sound.play("menu_move")
            elif key in (pg.K_TAB,pg.K_PAGEUP,pg.K_PAGEDOWN):
                step = -1 if key == pg.K_PAGEUP or key == pg.K_TAB and pg.key.get_mods() & pg.KMOD_SHIFT else 1
                self.option_page = (self.option_page+step)%len(session_store.SETUP_PAGES)
                self.option_slot = 0
                self.menu_note = ""
                self.sound.play("menu_move")
            elif key in (pg.K_LEFT,pg.K_RIGHT,pg.K_RETURN):
                self.adjust_setting(-1 if key==pg.K_LEFT else 1)
            elif key == pg.K_r:
                for item in self.option_items:
                    self.options[item.key] = item.default
                    if item.key == "window_mode" and self.fullscreen:
                        self.change_window_mode(0)
                self.crouch_latched = False
                self.apply_options()
                self.persist_options()
                self.sound.play("menu_accept")
            elif key == pg.K_ESCAPE:
                self.state = "title"
            return
        if self.state in ("controls", "credits"):
            if key in (pg.K_RETURN, pg.K_ESCAPE, pg.K_SPACE):
                self.state = "title"
            return
        if self.state == "replays":
            if key == pg.K_ESCAPE:
                self.state = "title"
            elif key in (pg.K_UP, pg.K_DOWN, pg.K_w, pg.K_s):
                step = -1 if key in (pg.K_UP, pg.K_w) else 1
                self.replay_selection = (self.replay_selection + step) % len(LEVELS)
                self.sound.play("menu_move")
            elif key in (pg.K_RETURN, pg.K_SPACE):
                level = LEVELS[self.replay_selection]
                if level.id in self.unlocked:
                    self.start(level.id, replay=True)
                else:
                    self.sound.play("empty")
                    self.menu_note = "CONTINUE THE CAMPAIGN TO UNLOCK."
            return
        if self.state == "title":
            if key in (pg.K_UP, pg.K_w):
                self.selection = (self.selection - 1) % len(self.entries)
                self.sound.play("menu_move")
            elif key in (pg.K_DOWN, pg.K_s):
                self.selection = (self.selection + 1) % len(self.entries)
                self.sound.play("menu_move")
            elif key in (pg.K_RETURN, pg.K_SPACE):
                self.sound.play("menu_accept")
                self.menu_action()
            elif key == pg.K_ESCAPE and self.game:
                self.state = "play"
                self.sound.pause_score(False)
                self.grab(not self.game.showing_tally and self.game.player.health > 0)
            return
        game = self.game
        if key == pg.K_ESCAPE:
            self.return_to_title()
        elif game.showing_tally:
            if key in (pg.K_RETURN, pg.K_SPACE):
                self.continue_campaign()
            return
        elif game.player.health <= 0:
            if key == pg.K_RETURN:
                if game.revisiting:
                    game.player.health = 1
                    game.player.x,game.player.y,game.player.angle = game.level.spawn
                    game.player.vx = game.player.vy = game.player.air = game.player.vertical_speed = 0.
                    game.player.eye = game.world.elevation(game.player.x,game.player.y)+.95
                    game.shots.clear()
                    self.open_hub(game)
                else:
                    self.start(game.level.id,kit=game.entry,history=game.history,replay=game.replay,
                               supply_rule=game.supply_rule)
                    self.game.retained = game.retained
        elif key in (pg.K_e, pg.K_SPACE):
            previous=len(self.hub_findings)
            game.interact()
            if len(self.hub_findings)!=previous and self.notes_path:
                try:
                    session_store.save_notes(self.notes_path,self.hub_findings)
                except OSError:
                    game.message("ROAD NOTE FOUND. IT COULD NOT BE FILED.",3.2)
            if game.portal_request:
                self.travel(game.portal_request)
        elif game.in_hub:
            if key == pg.K_TAB:
                game.map = not game.map
        elif key == pg.K_r:
            if game.armory.start_reload(game):
                game.barks.say(game, "reload")
        elif key in (pg.K_h, pg.K_SCROLLLOCK) and not game.armory.fuse:
            game.armory.holstered = not game.armory.holstered
        elif pg.K_1 <= key <= pg.K_9:
            game.armory.select(key - pg.K_1, game)
        elif key in (pg.K_0,pg.K_MINUS,pg.K_EQUALS,pg.K_BACKSLASH,pg.K_BACKQUOTE):
            game.armory.select({pg.K_0:ROCKET,pg.K_MINUS:BOWLING,pg.K_EQUALS:KEG,
                                pg.K_BACKSLASH:COW,pg.K_BACKQUOTE:TEAT}[key],game)
        elif key in (pg.K_SEMICOLON, pg.K_QUOTE):
            game.armory.cycle(-1 if key == pg.K_SEMICOLON else 1, game)
        elif key == pg.K_BACKSPACE:
            game.player.angle = (game.player.angle + math.pi) % math.tau
        elif key in (pg.K_q, pg.K_LEFTBRACKET, pg.K_RIGHTBRACKET):
            game.inventory_slot = (game.inventory_slot + (-1 if key == pg.K_LEFTBRACKET else 1)) % len(ITEMS)
        elif key in (pg.K_f, pg.K_RETURN):
            game.use_item()
        elif key in (pg.K_c, pg.K_b, pg.K_m, pg.K_v, pg.K_x):
            game.use_item((pg.K_c, pg.K_b, pg.K_m, pg.K_v, pg.K_x).index(key))
        elif key == pg.K_TAB:
            game.map = not game.map
        elif key == pg.K_HOME:
            game.player.pitch = 0
        elif key == pg.K_CAPSLOCK:
            self.options["autorun"] ^= 1
            self.persist_options()
            self.notice("ALWAYS RUN ON" if self.options["autorun"] else "ALWAYS RUN OFF",1.3)
        elif key == pg.K_z and self.options["crouch"]:
            self.crouch_latched = not self.crouch_latched
        elif key == pg.K_y:
            self.sound.play("yee_haw")

    def read_pad(self, dt):
        """Optional gamepad. Silent no-op when no controller is connected."""
        idle = {"forward": 0., "strafe": 0., "turn": 0., "look": 0., "run": False, "fire": False,
                "alt": False, "jump": False, "crouch": False}
        if not getattr(self, "pad", None):
            if pg.joystick.get_count() and not self.smoke:
                try:
                    self.pad = pg.joystick.Joystick(0)
                    self.pad.init()
                except pg.error:
                    self.pad = None
            if not getattr(self, "pad", None):
                self.pad = None
                return idle
        pad = self.pad
        try:
            def axis(i):
                v = pad.get_axis(i) if i < pad.get_numaxes() else 0.
                return 0. if abs(v) < .18 else v
            def button(i):
                return i < pad.get_numbuttons() and pad.get_button(i)
            trig_r = pad.get_axis(5) if pad.get_numaxes() > 5 else -1.
            trig_l = pad.get_axis(4) if pad.get_numaxes() > 4 else -1.
            if self.state == "play":
                for index, action in ((2, "reload"), (3, "use"), (4, "prev"), (5, "next")):
                    down = button(index)
                    was = self.pad_down.get(index, False)
                    self.pad_down[index] = down
                    if down and not was:
                        self.key({"reload": pg.K_r, "use": pg.K_e, "prev": pg.K_SEMICOLON, "next": pg.K_QUOTE}[action])
            return {"forward": -axis(1), "strafe": axis(0), "turn": axis(2) * dt * 2.6,
                    "look": -axis(3) * dt * 55, "run": button(8) or button(9),
                    "fire": trig_r > 0. or button(7), "alt": trig_l > 0., "jump": button(0),
                    "crouch": button(1)}
        except pg.error:
            self.pad = None
            return idle

    def render(self):
        if self.state == "title":
            self.hud.title(self.canvas, self.selection, self.entries, self.menu_note)
        elif self.state == "setup":
            self.render_setup()
        elif self.state == "slots":
            self.render_slots()
        elif self.state == "replays":
            self.menu_panel("REPLAY LEVEL")
            for i, level in enumerate(LEVELS):
                color = AMBER if i == self.replay_selection else INK
                y = REPLAY_TOP + i*REPLAY_ROW + 4
                if i == self.replay_selection:
                    pg.draw.rect(self.canvas, (82,49,31), (19,y-4,282,24))
                self.hud.text(self.canvas, level.title, (26,y), "menu", color=color)
                status = "UNLOCKED" if level.id in self.unlocked else "LOCKED"
                self.hud.text(self.canvas, status, (292,y+1), color=color, right=True)
            self.hud.text(self.canvas, "REPLAY USES ITS OWN SAVE SLOT", (160,145), center=True)
            self.hud.text(self.canvas, self.menu_note or "ENTER START  /  ESC BACK", (160,172), center=True)
        elif self.state == "controls":
            self.menu_panel("HOW TO RAISE HELL")
            self.hud.text(self.canvas,"KEYS",(24,40),color=AMBER)
            self.hud.text(self.canvas,"ACTION",(132,40),color=AMBER)
            for i,(keys,action) in enumerate(CONTROL_ROWS):
                y=51+i*12
                if i%2==0:
                    pg.draw.rect(self.canvas,(33,23,19),(19,y-2,282,12))
                self.hud.text(self.canvas,keys,(24,y),"menu")
                self.hud.text(self.canvas,action,(132,y),"menu",color=(232,213,178))
            self.hud.text(self.canvas,"ESC BACK",(160,178),center=True)
        elif self.state == "credits":
            self.menu_panel("CREDITS")
            for i,(heading,lines) in enumerate((
                    ("THE 1997 INSPIRATION",("REDNECK RAMPAGE / XATRIX ENTERTAINMENT",)),
                    ("PHOTOGRAPHS",("JERRY JONES / KEITH ALLISON (CC BY-SA 2.0)",
                                    "ROADSIDE / JOHN MARGOLIES, LIBRARY OF CONGRESS")),
                    ("MATERIALS AND AUDIO",("PHOTO MATERIALS / POLY HAVEN",
                                           "FULL CREDITS IN THIRD_PARTY_NOTICES.MD")),
            )):
                y=44+i*41
                self.hud.text(self.canvas,heading,(25,y),color=AMBER)
                for j,line in enumerate(lines):
                    self.hud.text(self.canvas,line,(25,y+13+j*10))
            self.hud.text(self.canvas,"ESC BACK",(160,178),center=True)
        else:
            self.game.draw(self.canvas,crosshair=self.options["crosshair"],grade=self.palette.grade)
        self.palette.apply(self.canvas)
        viewport = self.viewport()
        if viewport.size!=self.screen.get_size():
            self.screen.fill((12,9,8))
        if self.screen.get_masks()==self.canvas.get_masks():
            pg.transform.scale(self.canvas,viewport.size,self.screen.subsurface(viewport))
        else:
            self.screen.blit(pg.transform.scale(self.canvas,viewport.size),viewport.topleft)
        if self.touch.visible(self.state):
            self.touch.draw(self.screen, self.state)
        pg.display.flip()

    def menu_panel(self,title):
        self.canvas.blit(self.art.get("title_backdrop"),(0,0))
        self.hud.panel(self.canvas,(12,9,296,182))
        self.hud.text(self.canvas,title,(160,18),"heading",AMBER,center=True)

    def viewport(self):
        w,h = self.screen.get_size()
        width,height = self.presentation_size(w,h,self.options["aspect"],self.fullscreen and self.fullscreen_mode==1)
        return pg.Rect((w-width)//2,(h-height)//2,width,height)

    @staticmethod
    def presentation_size(w,h,aspect,fill=False):
        if fill:
            return w,h
        if aspect == 2 and w >= WIDTH and h >= HEIGHT:
            step = min(w//WIDTH,h//HEIGHT)
            return WIDTH*step,HEIGHT*step
        a,b = (8,5) if aspect else (4,3)
        return max(1,min(w,h*a//b)),max(1,min(h,w*b//a))

    def render_setup(self):
        canvas = self.canvas
        self.menu_panel("HICKSTON SETUP")
        for j,(label,_) in enumerate(session_store.SETUP_PAGES):
            x = SETUP_X+SETUP_TAB*j
            active = j==self.option_page
            pg.draw.rect(canvas,(100,61,33) if active else (54,39,32),(x,39,SETUP_TAB-2,14))
            pg.draw.line(canvas,(181,131,76) if active else (93,69,53),(x,39),(x+SETUP_TAB-3,39))
            self.hud.text(canvas,label,(x+(SETUP_TAB-2)//2,43),color=AMBER if active else INK,center=True)
        for j,item in enumerate(self.option_items):
            y = SETUP_Y+j*SETUP_ROW
            active = j==self.option_slot
            pg.draw.rect(canvas,(83,52,33) if active else (34,24,20) if j%2==0 else (40,29,23),
                         (SETUP_X,y,274,SETUP_ROW))
            self.hud.text(canvas,item.label,(35,y+2),"menu",color=AMBER if active else INK)
            self.hud.text(canvas,item.format(self.options[item.key]),(234,y+2),"menu",
                          color=AMBER if active else INK,center=True)
            if active:
                self.hud.text(canvas,">",(26,y+3),color=AMBER)
                self.hud.text(canvas,"<",(173,y+3),color=AMBER)
                self.hud.text(canvas,">",(291,y+3),color=AMBER)
        for i,line in enumerate(wrap(self.menu_note or self.option_items[self.option_slot].hint,272)):
            self.hud.text(canvas,line,(160,155+i*9),color=(227,201,161),center=True)
        pg.draw.line(canvas,(113,80,54),(23,174),(296,174))
        for x,guide in ((23,"TAB PAGES"),(99,"ARROWS CHANGE"),(192,"R RESET"),(249,"ESC BACK")):
            self.hud.text(canvas,guide,(x,179))

    def render_slots(self):
        kind = "REPLAY" if self.slot_replay else "CAMPAIGN"
        self.menu_panel(kind+" SAVE SLOTS")
        for mode,x in (("save",23),("load",161)):
            pg.draw.rect(self.canvas,(96,58,34) if self.slot_mode==mode else (53,37,29),(x,35,135,13))
            self.hud.text(self.canvas,mode.upper(),(x+67,38),center=True)
        for i,(_,digest,meta) in enumerate(self.slots):
            y = SLOT_TOP+i*SLOT_ROW
            active = self.slot_index==i
            pg.draw.rect(self.canvas,(75,48,32) if active else (39,28,22),(23,y,273,SLOT_ROW-2))
            label,level,stamp = (meta[0],meta[1].upper(),meta[3]) if meta else (
                "FILE UNREADABLE" if digest=="" else "EMPTY", "", "")
            self.hud.text(self.canvas,f"{i+1}  {label}",(28,y+4),color=AMBER if active else INK)
            self.hud.text(self.canvas,level,(291,y+4),right=True)
            self.hud.text(self.canvas,stamp,(28,y+14),"mini",shadow=False)
        meta = self.slots[self.slot_index][2]
        if self.slot_stage=="edit":
            lines = ("NAME  "+(self.slot_name or (meta[0] if meta else f"SLOT {self.slot_index+1}"))+"_",)
            guide = "ENTER CONTINUE / ESC CANCEL"
        elif self.slot_stage=="overwrite":
            lines = ("REPLACE "+meta[0]+"?",)
            guide = "ENTER OVERWRITE / ESC KEEP SAVE"
        else:
            lines = wrap(self.menu_note or (meta[2] if meta else "QUICKSAVE IS SEPARATE."),270)[:2]
            guide = "TAB SAVE / LOAD   ENTER SELECT   ESC BACK"
        for i,line in enumerate(lines):
            self.hud.text(self.canvas,line,(160,153+i*9),color=AMBER,center=True)
        self.hud.text(self.canvas,guide,(160,179),"mini",center=True)

    def click(self,position,button):
        rect = self.viewport()
        if not rect.collidepoint(position):
            return
        x = (position[0]-rect.x)*WIDTH//rect.w
        y = (position[1]-rect.y)*HEIGHT//rect.h
        if self.state == "title" and button==1 and 16<=x<190 and TITLE_FIRST<=y:
            row = (y-TITLE_FIRST)//title_row_height(self.entries)
            if row < len(self.entries):
                self.selection = row
                self.sound.play("menu_accept")
                self.menu_action()
                if self.state=="play":
                    self.block_fire = True
        elif self.state=="slots" and button==1:
            if self.slot_stage!="choose":
                if 171<=y<190:
                    self.key_slots(pg.K_RETURN if x<160 else pg.K_ESCAPE)
            elif 23<=x<296 and 35<=y<48:
                self.slot_mode = "save" if x<160 else "load"
                self.menu_note = ""
            elif 23<=x<296 and SLOT_TOP<=y<SLOT_TOP+SLOT_ROW*len(self.slots):
                self.slot_index = (y-SLOT_TOP)//SLOT_ROW
                self.key_slots(pg.K_RETURN)
            elif y>=171 and x>=228:
                self.key_slots(pg.K_ESCAPE)
        elif (self.state=="replays" and button==1 and 19<=x<301
              and REPLAY_TOP<=y<REPLAY_TOP+REPLAY_ROW*len(LEVELS)):
            self.replay_selection = (y-REPLAY_TOP)//REPLAY_ROW
            self.key(pg.K_RETURN)
        elif self.state=="setup" and button in (1,3):
            if button==1 and SETUP_X<=x<SETUP_X+SETUP_TAB*len(session_store.SETUP_PAGES) and 39<=y<54:
                self.option_page = (x-SETUP_X)//SETUP_TAB
                self.option_slot = 0
                self.menu_note = ""
                self.sound.play("menu_move")
            elif SETUP_X<=x<298 and SETUP_Y<=y<SETUP_Y+SETUP_ROW*len(self.option_items):
                self.option_slot = (y-SETUP_Y)//SETUP_ROW
                if x>=171:
                    self.adjust_setting(-1 if button==3 or x<183 else 1)
            elif button==1 and 175<=y<190 and 246<=x<=299:
                self.state = "title"

    def advance(self, elapsed, controls):
        self.accumulator = min(.1,self.accumulator+elapsed)
        self.pending_turn += controls.turn
        self.pending_look += controls.look
        steps = int((self.accumulator+1e-9)/SIM_STEP)
        if not steps:
            return
        self.accumulator = max(0.,self.accumulator-steps*SIM_STEP)
        controls.turn = self.pending_turn/steps
        controls.look = self.pending_look/steps
        self.pending_turn = self.pending_look = 0.
        for _ in range(steps):
            self.game.tick(SIM_STEP,controls)
            if self.game.portal_request:
                self.travel(self.game.portal_request)
                break

    async def loop(self, limit=0, marker=None):
        frames = 0
        while self.running:
            dt = min(.08, self.clock.tick((30,60,120)[self.options["frame_limit"]]) / 1000)
            self.touch.tick(dt)
            for event in pg.event.get():
                if event.type == pg.QUIT:
                    self.running = False
                elif event.type == pg.KEYDOWN and self.focused:
                    self.key(event.key)
                elif event.type == pg.TEXTINPUT and self.focused and self.state=="slots" and self.slot_stage=="edit":
                    self.slot_name = session_store.slot_label(self.slot_name+event.text)
                elif event.type in (pg.FINGERDOWN, pg.FINGERMOTION, pg.FINGERUP):
                    width, height = self.screen.get_size()
                    if self.state != "play":
                        self.touch.active = True
                        if event.type == pg.FINGERDOWN:
                            self.click((int(event.x * width), int(event.y * height)), 1)
                    else:
                        self.touch.event(event, (width, height))
                elif event.type == pg.MOUSEBUTTONDOWN and self.focused and self.state in ("title","setup","replays","slots"):
                    self.click(event.pos,event.button)
                elif event.type == pg.MOUSEBUTTONDOWN and self.focused and event.button==2 and self.state=="play" and not self.game.showing_tally:
                    self.key(pg.K_e)
                elif (event.type == pg.MOUSEWHEEL and self.focused and event.y and self.state == "play"
                      and self.game.player.health > 0 and not self.game.showing_tally and not self.game.in_hub):
                    self.game.armory.cycle(1 if event.y > 0 else -1, self.game)
                elif event.type == pg.WINDOWFOCUSLOST and not self.smoke:
                    if pg.time.get_ticks()<self.focus_grace:
                        continue
                    self.focused = False
                    self.block_fire = True
                    if self.state=="play":
                        self.game.player.vx = self.game.player.vy = 0.
                    if self.state=="play" and not self.game.showing_tally and self.options["focus_pause"]:
                        self.state = "title"
                        self.selection = 0
                        self.sound.pause_world()
                        self.sound.pause_score(True)
                    self.grab(False)
                elif event.type == pg.WINDOWFOCUSGAINED and not self.smoke:
                    self.focused = True
                    self.block_fire = True
                    if self.state=="play":
                        self.grab(not self.game.showing_tally and self.game.player.health>0)
            mx, my = pg.mouse.get_rel()
            pad = self.read_pad(dt)
            touch = self.touch.state()
            if self.state == "play" and self.game:
                if self.touch.consume_menu():
                    self.key(pg.K_ESCAPE)
                if self.state == "play":
                    if self.touch.consume_use():
                        self.key(pg.K_e)
                    if self.touch.consume_next() and not self.game.in_hub:
                        self.game.armory.cycle(1, self.game)
            if self.state=="play" and not self.focused:
                # With background play enabled, time advances with neutral input.
                # A held fuse keeps cooking without a synthetic release event.
                self.advance(dt,Controls(fire=bool(self.game.armory.fuse)))
            elif self.state == "play":
                keys = pg.key.get_pressed()
                mb = pg.mouse.get_pressed()
                if self.block_fire and not (mb[0] or mb[2] or keys[pg.K_LCTRL]):
                    self.block_fire = False
                sensitivity = self.options["sensitivity"]/100
                arrows = float(keys[pg.K_RIGHT])-float(keys[pg.K_LEFT])
                strafe_mode = keys[pg.K_LALT] or keys[pg.K_RALT]
                turn = 0. if strafe_mode else arrows*dt*2.1
                strafe = float(keys[pg.K_d])-float(keys[pg.K_a]) + (arrows if strafe_mode else 0.)
                look = (float(keys[pg.K_PAGEUP])-float(keys[pg.K_PAGEDOWN])) * dt*55
                sprint = bool(self.options["autorun"]) ^ bool(keys[pg.K_LSHIFT] or keys[pg.K_RSHIFT])
                self.advance(dt, Controls(
                    max(-1.,min(1.,float(keys[pg.K_w] or keys[pg.K_UP]) - float(keys[pg.K_s] or keys[pg.K_DOWN]) + pad["forward"] + touch["forward"])),
                    min(1.,max(-1.,strafe + pad["strafe"] + touch["strafe"])),
                    mx*.0034*sensitivity+turn+pad["turn"]+touch["turn"],
                    my*.24*(self.options["vertical"]/100)*(1 if self.options["invert"] else -1)+look+pad["look"],
                    sprint or pad["run"],
                    (mb[0] or keys[pg.K_LCTRL] or pad["fire"] or touch["fire"]) and not self.block_fire,
                    (mb[2] or pad["alt"] or touch["alt"]) and not self.block_fire, keys[pg.K_j] or pad["jump"],
                    self.crouch_latched if self.options["crouch"] else (keys[pg.K_z] or pad["crouch"])))
                if self.game.player.health <= 0:
                    self.sound.pause_score(True)
                if self.game.showing_tally or self.game.player.health <= 0:
                    self.grab(False)
            self.sound.tick_score(dt)
            self.render()
            frames += 1
            if limit and frames >= limit:
                if marker:
                    score=self.sound.score_player
                    music=(f"{score.active}/{score.track}; playing {pg.mixer.music.get_busy()}"
                           if score else "mixer unavailable")
                    Path(marker).write_text(f"{TITLE}\nVersion: {VERSION}\nSDL driver: {pg.display.get_driver()}\n"
                                            f"Audio mixer: {pg.mixer.get_init()}\n"
                                            f"Level: {self.game.level.id if self.game else 'title'}; score: {music}\n"
                                            f"Fullscreen: {self.fullscreen}; viewport: {self.viewport().size};"
                                            f" display: {self.screen.get_size()}\n{frames} frames rendered\n"
                                            f"{'Isolated save/load passed' if self.smoke and self.profile else ''}\n",
                                            encoding="utf-8")
                return
            await asyncio.sleep(0)


async def main():
    parser = argparse.ArgumentParser(prog="CrazyLegsMundellRampage")
    parser.add_argument("--smoke-frames", type=int, default=0, help=argparse.SUPPRESS)
    parser.add_argument("--smoke-marker", help=argparse.SUPPRESS)
    parser.add_argument("--smoke-fullscreen",action="store_true",help=argparse.SUPPRESS)
    parser.add_argument("--smoke-level", choices=BY_ID, default="hickston", help=argparse.SUPPRESS)
    parser.add_argument("--smoke-save",type=Path,help=argparse.SUPPRESS)
    args = parser.parse_args()
    if args.smoke_save and (not args.smoke_frames or args.smoke_save.exists()):
        parser.error("Smoke save needs a fresh profile path and a frame limit.")
    desktop = Desktop(smoke=bool(args.smoke_frames),profile=args.smoke_save)
    try:
        if args.smoke_frames:
            if args.smoke_fullscreen:
                desktop.change_window_mode(1)
            desktop.render()
            desktop.start(args.smoke_level,replay=bool(args.smoke_save and args.smoke_level!="hickston"))
            if args.smoke_save:
                desktop.game.player.health = 83
                desktop.save_game()
                desktop.game.player.health = 19
                desktop.load_game()
                if desktop.game.level.id!=args.smoke_level or desktop.game.player.health!=83:
                    raise RuntimeError("Packaged quicksave did not round-trip.")
        await desktop.loop(args.smoke_frames, args.smoke_marker)
    finally:
        pg.quit()


if __name__ == "__main__":
    os.environ.setdefault("PYGAME_HIDE_SUPPORT_PROMPT", "1")
    asyncio.run(main())


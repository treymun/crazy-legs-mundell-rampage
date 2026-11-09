"""Multi-touch gamepad overlay for Android and touchscreen desktops.

The overlay stays invisible for mouse/keyboard play and switches on for Android
or as soon as the first finger touches the window. A left thumbstick drives
movement, a right drag turns the camera, and four buttons cover fire, use,
alt-fire and weapon cycling. Every finger is tracked by ``finger_id`` so the
player can walk, aim and shoot at the same time.
"""
from __future__ import annotations

import math

import pygame as pg

from resource_path import IS_ANDROID


class TouchControls:
    DEADZONE = 0.16
    TURN_RATE = 0.0060
    TAP_SLOP = 0.022
    TAP_TIME = 0.45

    def __init__(self):
        self.active = IS_ANDROID
        self.size = (0, 0)
        self.fingers = {}
        self.stick = (0.0, 0.0)
        self.turn = 0.0
        self.fire = False
        self.alt = False
        self.use_count = 0
        self.next_count = 0
        self.menu_count = 0
        self.tap = None
        self.stick_center = (0.0, 0.0)
        self.stick_radius = 1.0
        self.buttons = []
        self.font = None
        self.layer = pg.Surface((1, 1), pg.SRCALPHA)
        self.clock = 0.0

    # ---------------------------------------------------------------- layout
    def layout(self, size):
        if size == self.size:
            return
        self.size = size
        m = max(1, min(size))
        self.stick_radius = m * .18
        self.stick_center = (size[0] * .16, size[1] * .70)
        r = m * .125
        small = m * .072
        self.buttons = [
            ("fire", size[0] * .87, size[1] * .72, r),
            ("use", size[0] * .68, size[1] * .85, small),
            ("alt", size[0] * .73, size[1] * .55, small),
            ("next", size[0] * .91, size[1] * .50, small),
            ("menu", size[0] * .95, size[1] * .10, small * .78),
        ]
        self.font = pg.font.Font(None, max(14, round(m * .028)))
        self.layer = pg.Surface(size, pg.SRCALPHA)
        self.fingers.clear()
        self.stick = (0.0, 0.0)
        self.fire = self.alt = False

    def _hit_button(self, pos):
        for role, cx, cy, radius in self.buttons:
            if math.hypot(pos[0] - cx, pos[1] - cy) <= radius:
                return role
        return None

    def _button_center(self, role):
        for name, cx, cy, radius in self.buttons:
            if name == role:
                return cx, cy
        return 0.0, 0.0

    def _stick(self, pos):
        dx = (pos[0] - self.stick_center[0]) / self.stick_radius
        dy = (pos[1] - self.stick_center[1]) / self.stick_radius
        length = math.hypot(dx, dy)
        if length > 1.0:
            dx, dy = dx / length, dy / length
        if length < self.DEADZONE:
            return 0.0, 0.0
        scale = min(1.0, (length - self.DEADZONE) / (1.0 - self.DEADZONE))
        return dx * scale, dy * scale

    # ---------------------------------------------------------------- events
    def event(self, event, size):
        self.layout(size)
        w, h = size
        if event.type == pg.FINGERDOWN:
            self.active = True
            pos = (event.x * w, event.y * h)
            finger = getattr(event, "finger_id", 0)
            if math.hypot(pos[0] - self.stick_center[0], pos[1] - self.stick_center[1]) <= self.stick_radius * 1.35:
                self.fingers[finger] = {"role": "stick", "start": pos, "last": pos,
                                        "time": self.clock}
                self.stick = self._stick(pos)
            else:
                role = self._hit_button(pos)
                if role:
                    self.fingers[finger] = {"role": role, "start": pos, "last": pos,
                                            "time": self.clock}
                    if role == "use":
                        self.use_count += 1
                    elif role == "next":
                        self.next_count += 1
                    elif role == "menu":
                        self.menu_count += 1
                elif pos[0] > w * .42:
                    self.fingers[finger] = {"role": "drag", "start": pos, "last": pos,
                                            "time": self.clock}
                else:
                    self.fingers[finger] = {"role": "tap", "start": pos, "last": pos,
                                            "time": self.clock}
            self._refresh()
        elif event.type == pg.FINGERMOTION:
            finger = getattr(event, "finger_id", 0)
            state = self.fingers.get(finger)
            pos = (event.x * w, event.y * h)
            if not state:
                return
            if state["role"] == "stick":
                self.stick = self._stick(pos)
            elif state["role"] == "drag":
                delta = getattr(event, "dx", 0.0) * w
                if not delta:
                    delta = pos[0] - state["last"][0]
                self.turn += delta * self.TURN_RATE
            state["last"] = pos
        elif event.type == pg.FINGERUP:
            finger = getattr(event, "finger_id", 0)
            state = self.fingers.pop(finger, None)
            if state:
                moved = math.hypot(state["last"][0] - state["start"][0],
                                   state["last"][1] - state["start"][1])
                if state["role"] != "drag":
                    if moved <= w * self.TAP_SLOP and self.clock - state["time"] <= self.TAP_TIME:
                        self.tap = state["start"]
                elif moved <= w * self.TAP_SLOP and self.clock - state["time"] <= self.TAP_TIME:
                    self.tap = state["start"]
                if state["role"] == "stick" and not any(
                        s["role"] == "stick" for s in self.fingers.values()):
                    self.stick = (0.0, 0.0)
            self._refresh()

    def _refresh(self):
        self.fire = any(s["role"] == "fire" for s in self.fingers.values())
        self.alt = any(s["role"] == "alt" for s in self.fingers.values())

    def tick(self, dt):
        self.clock += dt

    # ---------------------------------------------------------------- output
    def state(self):
        sx, sy = self.stick
        turn, self.turn = self.turn, 0.0
        return {"forward": -sy, "strafe": sx, "turn": turn,
                "fire": self.fire, "alt": self.alt}

    def consume_use(self):
        value, self.use_count = self.use_count > 0, 0
        return value

    def consume_next(self):
        value, self.next_count = self.next_count > 0, 0
        return value

    def consume_menu(self):
        value, self.menu_count = self.menu_count > 0, 0
        return value

    def consume_tap(self):
        value, self.tap = self.tap, None
        return value

    def visible(self, state):
        return self.active and state == "play"

    # ------------------------------------------------------------------ draw
    def draw(self, screen, state):
        if not self.visible(state):
            return
        self.layout(screen.get_size())
        layer = self.layer
        layer.fill((0, 0, 0, 0))
        pressed = {s["role"] for s in self.fingers.values()}
        for role, cx, cy, radius in self.buttons:
            hot = role in pressed
            fill = (232, 182, 96, 148) if hot else (29, 24, 20, 108)
            edge = (255, 226, 160, 210) if hot else (231, 197, 138, 128)
            pg.draw.circle(layer, fill, (round(cx), round(cy)), round(radius))
            pg.draw.circle(layer, edge, (round(cx), round(cy)), round(radius), 2)
            label = {"fire": "FIRE", "use": "USE", "alt": "ALT", "next": "NEXT",
                     "menu": "MENU"}[role]
            text = self.font.render(label, True, (255, 242, 214))
            text.set_alpha(230 if hot else 180)
            layer.blit(text, text.get_rect(center=(round(cx), round(cy))))
        cx, cy = self.stick_center
        pg.draw.circle(layer, (22, 18, 16, 92), (round(cx), round(cy)), round(self.stick_radius))
        pg.draw.circle(layer, (231, 197, 138, 116), (round(cx), round(cy)),
                       round(self.stick_radius), 2)
        sx, sy = self.stick
        kx = cx + sx * self.stick_radius * .58
        ky = cy + sy * self.stick_radius * .58
        pg.draw.circle(layer, (238, 217, 178, 132), (round(kx), round(ky)),
                       round(self.stick_radius * .42))
        pg.draw.circle(layer, (255, 240, 208, 188), (round(kx), round(ky)),
                       round(self.stick_radius * .42), 2)
        screen.blit(layer, (0, 0))

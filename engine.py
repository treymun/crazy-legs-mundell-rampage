"""320x200 indexed-look software renderer with planar scene reflections."""
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path
import math

import numpy as np
import pygame as pg

from crossroads import running_water, screen_holes, tower_shadow
from county_detail import SURFACES
from level_hickston import TILE, TILES
from resource_path import get_resource_path

ASSETS = Path(get_resource_path("assets"))
WIDTH, HEIGHT, VIEW = 320, 200, 156
FOCAL = 230.
COLUMNS = np.arange(WIDTH, dtype=np.float32)
ROWS = np.arange(VIEW, dtype=np.float32)[:, None]
SCREEN_RAYS = (COLUMNS + .5 - WIDTH / 2) / FOCAL
WALL_GLOW = np.zeros(len(TILES), dtype=bool)
WALL_GLOW[[TILE["liquor"], TILE["eat"], TILE["window"]]] = True
IMPACT_MATERIAL = {TILE[finish.tile]:TILE[finish.base] for group in SURFACES.values() for finish in group}
IMPACT_SURFACES = {TILE[tile]:kind for kind,tiles in (
    ("metal",("tin","ship","steel_mesh","fair_iron","fair_gate","mill_tin","mill_pump",
              "quarry_iron","quarry_copper","hub_tank_shell","powder_panel")),
    ("plaster",("plaster","brick","cinder","tile","concrete","quarry_face","office_wall","tavern")),
    ("dirt",("dirt","grass","orchard","tracks","shoulder","gravel","quarry_dust",
             "mill_grit","fair_gravel","creek","asphalt","road","oil_asphalt")),
) for tile in tiles}


def impact_surface(tile):
    return IMPACT_SURFACES.get(IMPACT_MATERIAL.get(tile,tile),"wood")


@lru_cache(maxsize=4)
def texture_pixels(name):
    return pg.surfarray.array3d(pg.image.load(ASSETS / "tiles" / (name + ".png"))).swapaxes(0, 1)


@lru_cache(maxsize=1)
def wall_textures():
    return np.stack([texture_pixels(name) for name in TILES])


@dataclass
class Sprite:
    x: float
    y: float
    image: str
    height: float
    z: float = 0.
    glow: bool = False
    flip: bool = False
    translucent: bool = False
    body: bool = False
    plane: float | None = None
    hurt: float = 0.


@dataclass(frozen=True)
class WallMark:
    x: float
    y: float
    z: float
    ux: float
    uy: float
    image: str
    radius: float
    material: str = "wood"


@dataclass(frozen=True)
class GroundMark:
    x: float
    y: float
    z: float
    angle: float
    reach: float
    width: float
    image: str


class Art:
    def __init__(self):
        self.images = {}

    def get(self, name):
        if name not in self.images:
            self.images[name] = pg.image.load(ASSETS / "art" / (name + ".png")).convert_alpha()
        return self.images[name]


class Renderer:
    def __init__(self, world, art):
        self.world = world
        self.art = art
        self.surface = pg.Surface((WIDTH, VIEW))
        self.tiles = wall_textures()
        self.sky = texture_pixels(world.sky)
        self.sprite_pixels = {}
        self.body_pivots = {}
        self.floor_bounds = self.plane_bounds(world.ground, world.ground_heights, world.caps)
        self.roof_bounds = self.plane_bounds(world.roof, world.roof_heights)
        self.moving_floors = {}
        flows = (("creek",6),("mill_water",5)) if world.sky=="mill_sky" else (("creek",6),)
        for name,rate in flows:
            tile = TILE[name]
            heights = set(world.ground[world.floor==tile])
            heights.update(height for height,caps in world.caps.items() if any(cap.cap==name for cap in caps))
            for height in heights:
                self.moving_floors.setdefault(height,[]).append((tile,rate))
        self.road_and_hub = None
        if world.hub_gates:
            first = world.walls[:, [1,3]].max(axis=1) <= 34
            second = world.walls[:, [1,3]].min(axis=1) >= 33
            self.road_and_hub = (world.walls[first], world.walls[second])
        self.time = 0.
        self.world_motion = 0

    @staticmethod
    def plane_bounds(plane, heights, caps=None):
        bounds = {}
        # Resolve near horizontal surfaces first so the broad base floor does
        # not texture pixels already occupied by steps, counters or platforms.
        for height in heights if caps is None else reversed(heights):
            yy,xx = np.nonzero(plane == height)
            boxes = [(int(xx.min()),int(yy.min()),int(xx.max())+1,int(yy.max())+1)] if xx.size else []
            if caps:
                boxes.extend((cap.x0,cap.y0,cap.x1,cap.y1) for cap in caps.get(height,()))
            if boxes:
                bounds[height] = (min(p[0] for p in boxes),min(p[1] for p in boxes),
                                  max(p[2] for p in boxes),max(p[3] for p in boxes))
        return bounds

    @staticmethod
    def light_at(distance, light):
        # Stepped shades mimic an 8-bit shade lookup table.
        shade = np.maximum(.19, light / (1. + .102 * distance))
        return np.floor(shade * 32 + .5) / 32

    def cast(self, x, y, dx, dy, walls, minimum):
        x1, y1, x2, y2 = walls[:, :4].T
        ex, ey = x2 - x1, y2 - y1
        rx, ry = x1 - x, y1 - y
        denominator = dx[:, None] * ey - dy[:, None] * ex
        parallel = np.abs(denominator) < 1e-6
        safe = np.where(parallel, 1., denominator)
        t = (rx * ey - ry * ex) / safe
        u = (rx * dy[:, None] - ry * dx[:, None]) / safe
        valid = ~parallel & (t > minimum[:, None]) & (t < 160.) & (u >= -.00002) & (u <= 1.00002)
        t[~valid] = 160.
        layers = int(valid.sum(axis=1).max())
        c = np.arange(len(dx))[:, None]
        if 0 < layers < t.shape[1]//3:
            candidates = np.argpartition(t,layers-1,axis=1)[:,:layers]
            order=np.lexsort((candidates,t[c,candidates]),axis=1)
            nearest=candidates[c,order]
        else:
            nearest = np.argsort(t,axis=1,kind="stable")[:,:layers]
        tex_u = np.where(denominator[c, nearest] < 0, 1 - u[c, nearest], u[c, nearest])
        return t[c, nearest], tex_u, walls[nearest, 4:]

    def draw(self, player, sprites, reflection_sprite, flash=0., marks=(), ground_marks=()):
        at_crossroads = self.road_and_hub is not None and player.y > 33
        if at_crossroads:
            walls = self.road_and_hub[1]
            if self.world.locked_gates:
                barriers = np.asarray([gate.barrier() for gate in self.world.locked_gates],dtype=np.float32)
                walls = np.concatenate((walls,barriers))
        else:
            static = self.world.walls if self.road_and_hub is None else self.road_and_hub[0]
            walls = np.concatenate((static, self.world.door_walls()))
        horizon = VIEW / 2 + player.pitch + player.bob + player.sway
        z = player.eye
        frame, mirror_mask = self.scene(player.x, player.y, z, player.view_angle,
                                        horizon, 1, walls, sprites, flash,marks=marks,ground_marks=ground_marks)
        if self.world.mirror and mirror_mask.any():
            plane_x = self.world.mirror[0]
            ghost = [*sprites, reflection_sprite] if reflection_sprite else sprites
            edges = np.flatnonzero(mirror_mask.any(axis=0))
            columns = slice(edges[0], edges[-1] + 1)
            aperture = mirror_mask[:, columns]
            reflection, _ = self.scene(2 * plane_x - player.x, player.y, z,
                                       math.pi - player.view_angle, horizon, -1, walls, ghost, flash,columns,marks,
                                       ground_marks)
            reflected = frame[:, columns]
            reflected[aperture] = (reflection[aperture].astype(np.float32) * [.81, .86, .84]
                                   + [7, 8, 6]).astype(np.uint8)
            y, x = np.indices(aperture.shape)
            glass = aperture & ((x + columns.start + y * 2) % 61 == 0)
            reflected[glass] = (reflected[glass].astype(np.float32) * .88 + [14, 13, 11]).astype(np.uint8)
        pg.surfarray.blit_array(self.surface, frame.swapaxes(0, 1))
        return self.surface

    def scene(self, x, y, z, angle, horizon, parity, walls, sprites, flash,
              columns=slice(0, WIDTH),marks=(),ground_marks=()):
        forward = (math.cos(angle), math.sin(angle))
        right = (-forward[1] * parity, forward[0] * parity)
        rays = SCREEN_RAYS[columns]
        width = len(rays)
        # Reject segments entirely outside the view wedge before the ray matrix.
        # Keep whole segments when either endpoint can cross a side plane.
        ex = walls[:, (0, 2)] - x
        ey = walls[:, (1, 3)] - y
        ahead = ex * forward[0] + ey * forward[1]
        side = ex * right[0] + ey * right[1]
        edge = max(abs(rays[0]), abs(rays[-1])) + .012
        keep = ((ahead.max(axis=1) > 0) & ((ahead * edge - side).max(axis=1) >= 0)
                & ((ahead * edge + side).max(axis=1) >= 0))
        walls = walls[keep]
        dx = (forward[0] + right[0] * rays).astype(np.float32)
        dy = (forward[1] + right[1] * rays).astype(np.float32)
        minimum = np.full(width, .015, dtype=np.float32)
        if parity < 0:
            denom = np.where(np.abs(dx) > .00001, dx, -.00001)
            minimum = np.maximum(minimum, (self.world.mirror[0] - x) / denom + .008)
        distances, us, surfaces = self.cast(x, y, dx, dy, walls, minimum)
        sy = ROWS + .5 - horizon
        sky_angle = angle + parity * np.arctan(rays)
        sky_x = (sky_angle * (512 / (2 * math.pi))).astype(int) & 511
        sky_y = np.clip((93 + sy * .95).astype(int), 0, 115)
        # Two advanced indices already produce an independent frame buffer.
        frame = self.sky[sky_y, sky_x]
        depth = np.full((VIEW, width), 160., dtype=np.float32)
        split = int(np.count_nonzero(sy <= 0))
        glass = np.zeros((VIEW, width), dtype=bool)
        pane_dist,pane_color = None,None
        for layer in range(distances.shape[1]):
            d, u = distances[:, layer], us[:, layer]
            tiles, light, bottom, top, area = surfaces[:, layer].T
            tiles, area = tiles.astype(int), area.astype(int)
            wall_z = z - sy * d / FOCAL
            wall_mask = (wall_z >= bottom) & (wall_z <= top) & (d < depth)
            if not wall_mask.any():
                continue
            row, column = np.nonzero(wall_mask)
            wall_v = np.clip((top[column] - wall_z[row, column]) / (top[column] - bottom[column]) * 128,
                             0, 127).astype(int)
            wall_u = np.clip(u[column] * 128, 0, 127).astype(int)
            tile = tiles[column]
            samples = self.tiles[tile, wall_v, wall_u]
            grade = self.light_at(d[column], light[column] + flash)
            signs = WALL_GLOW[tile]
            if signs.any():
                signs[signs] = samples[signs].max(axis=-1) > 156
                grade[signs] = np.maximum(grade[signs], .9)
                if .87 < (self.time % 6.1) < 1.02:
                    grade[(tile == TILE["liquor"]) & signs] *= .73
            paint = self.shade(samples, grade, area[column])
            if self.road_and_hub is not None and y>33:
                receiver = tile == TILE["hub_service_wall"]
                if receiver.any():
                    rr,cc = row[receiver],column[receiver]
                    distance=d[cc]
                    shade = tower_shadow(x+distance*dx[cc],y+distance*dy[cc],wall_z[rr,cc],
                                         self.time,self.world_motion)
                    paint[receiver] = (paint[receiver]*shade[:,None]).astype(np.uint8)
                mesh = tile == TILE["hub_screen"]
                if mesh.any():
                    opaque = ~mesh | ~screen_holes(wall_u,wall_v)
                    row,column,tile,wall_u,wall_v,paint = (
                        value[opaque] for value in (row,column,tile,wall_u,wall_v,paint))
            glazing = tile == TILE["glazing"]
            if glazing.any():
                glazed = (glazing & (wall_u>5) & (wall_u<122) & ((wall_u<62)|(wall_u>67))
                          & (wall_v>6) & (wall_v<121) & ((wall_v<67)|(wall_v>73)))
                if glazed.any():
                    if pane_dist is None:
                        pane_dist=np.full((VIEW,width),160.,dtype=np.float32)
                        pane_color=np.zeros_like(frame)
                    rr,cc=row[glazed],column[glazed]
                    near=d[cc] < pane_dist[rr,cc]
                    pane_dist[rr[near],cc[near]]=d[cc[near]]
                    pane_color[rr[near],cc[near]]=paint[glazed][near]
                    opaque=~glazed
                    row,column,tile,wall_u,wall_v,paint = (
                        array[opaque] for array in (row,column,tile,wall_u,wall_v,paint))
            frame[row,column]=paint
            depth[row,column]=d[column]
            glass[row,column]=((tile==TILE["mirror"]) & (wall_u>=12) & (wall_u<116)
                               & (wall_v>=17) & (wall_v<108) & (parity>0))
        self.planes(frame[:split], depth[:split], glass[:split], sy[:split],
                    x, y, z, dx, dy, minimum, flash, True)
        self.planes(frame[split:], depth[split:], glass[split:], sy[split:],
                    x, y, z, dx, dy, minimum, flash, False)
        for mark in marks:
            self.draw_mark(frame,depth,glass,mark,x,y,z,forward,right,horizon,columns.start)
        edge_scale = math.hypot(1.,edge)
        for mark in ground_marks:
            mx,my = mark.x-x,mark.y-y
            reach = math.hypot(mark.reach,mark.width)
            ahead = mx*forward[0]+my*forward[1]
            side = mx*right[0]+my*right[1]
            # A bounding circle preserves every footprint that touches the
            # view wedge, including the narrower reflected view.
            if ahead+reach<=0. or abs(side)-ahead*edge>reach*edge_scale:
                continue
            self.draw_ground_mark(frame,depth,mark,x,y,z,dx,dy,sy,minimum)
        for sprite in sprites:
            self.draw_sprite(frame, depth, glass, sprite, x, y, z, forward, right,
                             horizon, parity, columns.start)
        if pane_dist is not None:
            cover=pane_dist<depth
            frame[cover]=np.clip(frame[cover]*[.67,.78,.82]+pane_color[cover]*.33,0,255)
        return frame, glass

    def draw_ground_mark(self,frame,depth,mark,x,y,z,dx,dy,sy,minimum):
        radial = math.hypot(mark.x-x,mark.y-y)
        if z <= mark.z+.015 or radial>26.:
            return
        distance = ((z-mark.z)*FOCAL) / np.maximum(sy[:,0],.015)
        bounds = math.hypot(mark.reach,mark.width)
        rows = np.flatnonzero((sy[:,0]>0)&(distance<radial+bounds+1.)&
                              (distance>max(0.,(radial-bounds)*.76)))
        if not rows.size:
            return
        d = distance[rows,None]
        wx,wy = (x-mark.x)+d*dx,(y-mark.y)+d*dy
        cs,sn = math.cos(mark.angle),math.sin(mark.angle)
        u = (wx*cs+wy*sn)/mark.reach
        v = (-wx*sn+wy*cs)/mark.width
        ir,col = ((np.abs(u)<1.)&(np.abs(v)<1.)&(d>minimum)&(np.abs(d-depth[rows])<.13)).nonzero()
        if not ir.size:
            return
        if mark.image not in self.sprite_pixels:
            art=self.art.get(mark.image)
            self.sprite_pixels[mark.image]=(pg.surfarray.array3d(art).swapaxes(0,1),
                                            pg.surfarray.array_alpha(art).T)
        rgb,alpha=self.sprite_pixels[mark.image]
        h,w=alpha.shape
        a=((u[ir,col]+1)*.5*w).astype(int)
        b=((v[ir,col]+1)*.5*h).astype(int)
        row=rows[ir]
        opacity=alpha[b,a,None]/255.
        colors=rgb[b,a]*(np.maximum(.63,self.light_at(distance[row],1.12))[:,None])
        frame[row,col]=np.rint(frame[row,col]*(1-opacity)+colors*opacity).astype(np.uint8)

    def wall_mark(self,x,y,z,ax,ay,slope,distance):
        # Use the same segment set that draws the scene, so an impact sits on
        # the textured face instead of hovering at the hitscan's sample point.
        w = self.world.walls
        ex,ey = w[:,2]-w[:,0],w[:,3]-w[:,1]
        rx,ry = w[:,0]-x,w[:,1]-y
        den = ax*ey-ay*ex
        safe = np.where(np.abs(den)<1e-6,1.,den)
        t,u = (rx*ey-ry*ex)/safe,(rx*ay-ry*ax)/safe
        height=z+t*slope
        valid=(np.abs(den)>=1e-6)&(np.abs(t-distance)<.19)&(t>.14)&(u>=0)&(u<=1)
        valid &= (height>w[:,6]+.02)&(height<w[:,7]-.02)&(w[:,4]!=TILE["mirror"])
        if not valid.any():
            return None
        i = int(np.argmin(np.where(valid,np.abs(t-distance),np.inf)))
        ox,oy=float(ex[i]),float(ey[i])
        length=math.hypot(ox,oy)
        material = impact_surface(int(w[i,4]))
        kind = "stone" if material in ("plaster","dirt") else material
        return WallMark(float(x+ax*t[i]),float(y+ay*t[i]),float(height[i]),ox/length,oy/length,
                        "fx_hole_"+kind,.051 if kind=="metal" else .060,material)

    def draw_mark(self,frame,depth,glass,mark,x,y,z,forward,right,horizon,offset):
        rx,ry = mark.x-x,mark.y-y
        d = rx*forward[0]+ry*forward[1]
        if not .19<d<15.:
            return
        lateral = rx*right[0]+ry*right[1]
        axis = mark.ux*right[0]+mark.uy*right[1]
        fall = mark.ux*forward[0]+mark.uy*forward[1]
        if abs(axis*d-lateral*fall) < .08:
            return
        extent=mark.radius
        left = WIDTH*.5-offset+(lateral-axis*extent)*FOCAL/(d-fall*extent)
        right_edge = WIDTH*.5-offset+(lateral+axis*extent)*FOCAL/(d+fall*extent)
        x0=max(0,int(math.floor(min(left,right_edge))))
        x1=min(frame.shape[1],int(math.ceil(max(left,right_edge))))
        half = FOCAL*extent/d
        cy=horizon-(mark.z-z)*FOCAL/d
        y0=max(0,int(cy-half-1))
        y1=min(VIEW,int(cy+half+2))
        if x0>=x1 or y0>=y1:
            return
        sample=self.sprite_pixels.get(mark.image)
        if sample is None:
            art=self.art.get(mark.image)
            sample=(pg.surfarray.array3d(art).swapaxes(0,1),pg.surfarray.array_alpha(art).T)
            self.sprite_pixels[mark.image]=sample
        rgb,alpha=sample
        if abs(right_edge-left)<.15:
            return
        pixels=np.arange(x0,x1)+.5
        proj=(pixels-(WIDTH*.5-offset))/FOCAL
        along=(proj*d-lateral)/(axis-proj*fall+1e-12)
        dd=d+along*fall
        vv=(horizon-(np.arange(y0,y1)[:,None]+.5))*dd/FOCAL + z - mark.z
        u=np.clip(((along/extent+1)*.5*alpha.shape[1]).astype(int),0,alpha.shape[1]-1)
        v=np.clip(((1-vv/extent)*.5*alpha.shape[0]).astype(int),0,alpha.shape[0]-1)
        region=np.s_[y0:y1,x0:x1]
        opacity=alpha[v,u]
        valid=(np.abs(depth[region]-dd)<.12)&(np.abs(along)<=extent)&(np.abs(vv)<=extent)&(opacity>20)&~glass[region]
        if valid.any():
            color=self.light_at(d,1.)*rgb[v,u][valid]
            mix=opacity[valid,None]/255.
            frame[region][valid]=np.rint(frame[region][valid]*(1-mix)+color*mix).astype(np.uint8)

    def planes(self, frame, depth, glass, sy, x, y, z, dx, dy, minimum, flash, overhead):
        if not len(sy):
            return
        world = self.world
        factor = FOCAL / np.maximum(.02, np.abs(sy[:,0]))
        heights = self.roof_bounds if overhead else self.floor_bounds
        sx = np.where(np.abs(dx)<1e-7,1e-7,dx)
        sy1 = np.where(np.abs(dy)<1e-7,1e-7,dy)
        for height,(x0,y0,x1,y1) in heights.items():
            if overhead and height<=z or not overhead and height>=z:
                continue
            t = np.minimum(np.abs(height - z) * factor, 80.)
            ax,bx = (x0-x)/sx,(x1-x)/sx
            ay,by = (y0-y)/sy1,(y1-y)/sy1
            begin = np.maximum(minimum,np.maximum(np.minimum(ax,bx),np.minimum(ay,by)))
            end = np.minimum(np.maximum(ax,bx),np.maximum(ay,by))
            # Bound the screen rectangle before allocating the depth mask.
            # Exact per-ray bounds still apply inside the candidate span.
            rays = np.flatnonzero(begin<=end)
            if not rays.size:
                continue
            rows = np.flatnonzero((t>=begin[rays].min())&(t<=end[rays].max()))
            if not rows.size:
                continue
            left,right = rays[0],rays[-1]+1
            low,high = rows[0],rows[-1]+1
            span = t[low:high,None]
            candidate = (span>=begin[left:right])&(span<=end[left:right])&(span<depth[low:high,left:right])
            row,col = candidate.nonzero()
            row+=low
            col+=left
            if not row.size:
                continue
            distance = t[row]
            wx, wy = x + distance*dx[col], y + distance*dy[col]
            ix = np.clip(np.floor(wx).astype(np.int16), 0, world.solid.shape[1] - 1)
            iy = np.clip(np.floor(wy).astype(np.int16), 0, world.solid.shape[0] - 1)
            if overhead:
                present = world.roof[iy, ix] == height
                tile = world.ceiling[iy, ix]
            else:
                present = world.ground[iy, ix] == height
                tile = world.floor[iy, ix]
                for fixture in world.caps.get(height, ()):
                    cap = (wx >= fixture.x0) & (wx <= fixture.x1) & (wy >= fixture.y0) & (wy <= fixture.y1)
                    present |= cap
                    tile[cap] = TILE[fixture.cap]
            if not present.any():
                continue
            row,col = row[present],col[present]
            iy,ix = iy[present],ix[present]
            u = np.floor(wx[present] * 128).astype(np.int16) & 127
            v = np.floor(wy[present] * 128).astype(np.int16) & 127
            distance = distance[present]
            light = self.light_at(distance, world.light[iy, ix] * (.77 if overhead else .94) + flash)
            tile = tile[present]
            if not overhead:
                for flow,rate in self.moving_floors.get(height,()):
                    wet = tile==flow
                    v[wet] = (v[wet]+int(self.time*rate))&127
            rgb = self.tiles[tile,v,u]
            if not overhead and self.road_and_hub is not None and y>33:
                receiver = (tile == TILE["hub_patch"]) | (tile == TILE["hub_service_wall"])
                if receiver.any():
                    light[receiver] *= tower_shadow(wx[present][receiver],wy[present][receiver],
                                                    height,self.time,self.world_motion)
                drain = tile == TILE["hub_runoff"]
                if drain.any():
                    rgb[drain] = running_water(rgb[drain],wx[present][drain],wy[present][drain],
                                               self.time,self.world_motion)
            frame[row,col] = self.shade(rgb, light, world.area[iy,ix])
            depth[row,col] = distance
            glass[row,col] = False

    def shade(self, rgb, light, area):
        return np.clip(rgb * np.asarray(light)[..., None] * self.world.tints[area], 0, 255).astype(np.uint8)

    def body_foot_offset(self,name,alpha,height):
        if name not in self.body_pivots:
            occupied = np.flatnonzero((alpha>100).any(axis=1))
            self.body_pivots[name] = (alpha.shape[0]-1-int(occupied[-1]))/alpha.shape[0] if occupied.size else 0.
        return round(height*self.body_pivots[name])

    def draw_sprite(self, frame, depth, glass, sprite, x, y, z, forward, right, horizon, parity, offset):
        dx, dy = sprite.x - x, sprite.y - y
        if parity < 0 and sprite.x < self.world.mirror[0]:
            return
        dist = dx * forward[0] + dy * forward[1]
        if not .13 < dist < (51 if sprite.height > 2.7 else 32):
            return
        lateral = dx * right[0] + dy * right[1]
        screen_x = WIDTH / 2 + lateral / dist * FOCAL - offset
        viewport_width = frame.shape[1]
        height = int(sprite.height / dist * FOCAL)
        if height < 2:
            return
        if sprite.plane is None:
            top = round(horizon - (sprite.z + sprite.height - z) / dist * FOCAL)
            if top>=VIEW or (top+height<=0 and not sprite.body):
                return
        if sprite.image not in self.sprite_pixels:
            art = self.art.get(sprite.image)
            rgb = pg.surfarray.array3d(art).swapaxes(0, 1)
            a = pg.surfarray.array_alpha(art).T
            self.sprite_pixels[sprite.image] = rgb, a
        rgb, alpha = self.sprite_pixels[sprite.image]
        if sprite.plane is not None:
            self.draw_sign(frame,depth,glass,sprite,x,y,z,forward,right,horizon,offset,rgb,alpha)
            return
        src_h, src_w = alpha.shape
        width = max(1, int(height * src_w / src_h))
        if screen_x < -width / 2 or screen_x > viewport_width + width / 2:
            return
        left = round(screen_x - width / 2)
        if sprite.body:
            top += self.body_foot_offset(sprite.image,alpha,height)
        x0, x1 = max(0, left), min(viewport_width, left + width)
        y0, y1 = max(0, top), min(VIEW, top + height)
        if x0 >= x1 or y0>=y1:
            return
        sx = (np.arange(x0, x1) - left) * src_w // width
        sy = (np.arange(y0, y1) - top) * src_h // height
        if sprite.flip != (parity < 0):
            sx = src_w - sx - 1
        region = np.s_[y0:y1, x0:x1]
        opacity = alpha[sy[:, None], sx]
        mask = (opacity > (12 if sprite.translucent else 100)) & (dist < depth[region] + .014)
        if not mask.any():
            return
        iy, ix = int(sprite.y), int(sprite.x)
        light = 1.1 if sprite.glow else self.light_at(dist, self.world.light[iy, ix])
        if sprite.body:
            light = max(light, .58 - .021*dist)
        area = 1 if sprite.glow else self.world.area[iy, ix]
        colors = self.shade(rgb[sy[:, None], sx][mask], light, area)
        if sprite.hurt > 0.:
            # Damage flash: wash toward hot white so hits read at any distance.
            k = min(.46, sprite.hurt / .18 * .44)
            colors = (colors * (1. - k) + np.array((255, 232, 208)) * k).astype(np.uint8)
        if sprite.translucent:
            coverage = opacity[mask][:, None] / 255.
            colors = np.rint(frame[region][mask] * (1 - coverage) + colors * coverage).astype(np.uint8)
        else:
            depth[region][mask] = dist
        frame[region][mask] = colors
        glass[region][mask] = False

    def draw_sign(self, frame, depth, glass, sprite, x, y, z, forward, right, horizon, offset, rgb, alpha):
        """Project a painted board along its world axis so it shares the frame's perspective."""
        ax,ay = math.cos(sprite.plane), math.sin(sprite.plane)
        rx,ry = sprite.x-x,sprite.y-y
        side = rx*ay - ry*ax
        if side <= .02:
            return
        rays = SCREEN_RAYS[offset:offset+frame.shape[1]]
        sy,sx = alpha.shape
        width = sprite.height*sx/sy
        near,far = float(rays[0]),float(rays[-1])
        ahead = rx*forward[0]+ry*forward[1]
        lateral = rx*right[0]+ry*right[1]
        half_ahead = (ax*forward[0]+ay*forward[1])*width*.5
        half_lateral = (ax*right[0]+ay*right[1])*width*.5
        # Reject only when both endpoints lie beyond the same screen edge.
        # A corner crossing either plane must still reach the ray/depth pass.
        if (near*ahead-lateral>abs(near*half_ahead-half_lateral)+.002
                or lateral-far*ahead>abs(half_lateral-far*half_ahead)+.002):
            return
        dx,dy = forward[0]+right[0]*rays,forward[1]+right[1]*rays
        denominator = ay*dx-ax*dy
        distances = np.divide(side,denominator,out=np.zeros_like(rays),where=denominator>.001)
        along = ((x-sprite.x+dx*distances)*ax+(y-sprite.y+dy*distances)*ay)/width+.5
        cols = np.flatnonzero((distances>.13)&(along>=0.)&(along<1.))
        if not cols.size:
            return
        d = distances[cols]
        v = (sprite.z+sprite.height-z+(ROWS+.5-horizon)*d/FOCAL)/sprite.height
        row,i = np.nonzero((v>=0.)&(v<1.)&(d<depth[:,cols]+.012))
        col = cols[i]
        u = (along[col]*sx).astype(int)
        vv = (v[row,i]*sy).astype(int)
        painted = alpha[vv,u] > (12 if sprite.translucent else 100)
        row,col,u,vv = (values[painted] for values in (row,col,u,vv))
        if row.size:
            iy,ix = int(sprite.y),int(sprite.x)
            light = self.light_at(distances[col], self.world.light[iy,ix])
            color = self.shade(rgb[vv,u],light,self.world.area[iy,ix])
            if sprite.translucent:
                amount = alpha[vv,u,None]/255.
                frame[row,col] = np.rint(frame[row,col]*(1.-amount)+color*amount).astype(np.uint8)
            else:
                frame[row,col] = color
                depth[row,col] = distances[col]
                glass[row,col] = False


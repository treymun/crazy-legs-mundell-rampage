"""Authored dressing placed against existing county fixtures and routes."""
from dataclasses import dataclass
from math import pi


@dataclass(frozen=True)
class Site:
    name: str
    x: float
    y: float
    z: float
    height: float
    plane: float | None = None
    wear: tuple | None = None

    @property
    def image(self):
        return f"detail_{self.name}"


@dataclass(frozen=True)
class Surface:
    name: str
    base: str
    bounds: tuple
    finish: str
    tone: tuple

    @property
    def tile(self):
        return f"detail_wall_{self.name}"


SURFACES = {
    "hickston": (
        Surface("bar_wainscot","tavern",(5.9,16.9,7.1,20.1),"bar wainscot",(95,73,56)),
        Surface("garage_courses","brick",(54,15.75,61.3,21.1),"oil paint",(71,76,67)),
        Surface("feed_pen_boards","barn",(63.5,25.5,71.6,30.85),"skirting",(90,69,49)),
    ),
    "fair": (
        Surface("raffle_stripes","fair_booth",(44,22,63,33.75),"fair stripes",(117,72,57)),
        Surface("prize_skirting","fair_prize",(57.5,35.8,62.1,38.2),"skirting",(95,68,67)),
    ),
    "sawmill": (
        Surface("kiln_patches","mill_tin",(58.6,25.9,66.6,32.8),"riveted patches",(114,106,84)),
        Surface("rain_sheets","mill_tin",(46.7,34.7,55.9,39.7),"runoff",(78,95,97)),
    ),
    "quarry": (
        Surface("chalk_cut","quarry_face",(49,20.1,69,33.9),"fractures",(166,145,109)),
        Surface("copper_seams","quarry_copper",(69.5,16.8,74.4,20.0),"riveted patches",(130,94,61)),
    ),
    "hub": (
        Surface("shed_repair","mill_tin",(29.0,42.1,34.95,48.1),"riveted patches",(110,104,87)),
        Surface("approach_fence","stockyard",(13.0,35.1,26.0,41.1),"skirting",(84,85,66)),
    ),
}


DETAIL_TILES = tuple(surface.tile for group in SURFACES.values() for surface in group)


# Z is relative to the local floor. Table props sit on the existing collision
# caps. Shallow wall fittings use the visible face of the supporting surface.
SITES = {
    "hickston": (
        Site("bar_backstock",9.02,18.45,.78,.52),
        Site("dispatch_rack",12.59,9.34,.78,.54,0.),
        Site("feed_sampler",27.12,19.50,.72,.47),
        Site("trailer_service",36.83,20.53,.008,.49,pi),
        Site("tire_patch_bench",56.77,18.36,.82,.55,pi/2,(57.65,18.96,.7,.94,.47,"oil")),
        Site("tow_spool",59.08,9.43,.69,.62),
        Site("registry_stamp",76.05,11.07,.81,.50,pi/2),
        Site("railhead_sacks",91.27,27.74,.73,.53,None,(91.14,26.53,.28,1.04,.44,"grain")),
    ),
    "fair": (
        Site("ticket_rolls",26.75,32.40,.79,.48),
        Site("soda_fountain",7.68,25.22,.808,.66,0.,(7.78,26.12,0.,.84,.41,"soda")),
        Site("prize_cubbies",17.70,12.92,.06,.56,0.),
        Site("stage_footlights",20.54,10.16,1.14,.23,0.),
        Site("freight_cartons",48.22,26.68,.67,.54,None,(47.84,25.47,.16,1.14,.53,"tickets")),
        Site("raffle_drawer",46.81,30.925,.14,.54,pi),
        Site("pa_cable_case",55.84,8.36,.85,.52,0.),
        Site("lost_property_tray",64.30,35.42,.89,.52),
    ),
    "sawmill": (
        Site("delivery_chocks",18.27,29.31,.72,.55,None,(19.65,30.33,-.5,1.2,.46,"sawdust")),
        Site("sluice_winder",10.97,22.18,.59,.68),
        Site("carriage_tools",25.57,14.75,.73,.57,0.),
        Site("pump_manifold",26.68,9.54,.009,.65,0.),
        Site("sort_chain_box",55.93,23.69,.74,.62,0.),
        Site("kiln_duct",64.04,30.36,.89,.77,0.),
        Site("rain_stock",49.44,36.62,.74,.55,None,(49.37,37.77,.1,.95,.56,"sawdust")),
        Site("apron_blade_rack",15.19,4.42,.77,.76,0.),
    ),
    "quarry": (
        Site("scale_weights",21.72,35.69,.83,.53),
        Site("cutting_drill",9.77,14.62,.79,.60,None,(10.75,14.64,.2,1.04,.52,"chalk")),
        Site("still_gauge_bank",45.18,19.03,.79,.68,-pi/2),
        Site("bottling_cradles",30.99,14.41,.75,.49),
        Site("lower_core_samples",52.98,23.98,.78,.51),
        Site("recovery_seal_kit",73.99,18.05,.72,.52,None,(73.95,19.25,.8,1.03,.47,"copper")),
        Site("wash_rejects",73.29,35.69,.89,.46,0.),
        Site("relief_spanner_box",30.52,7.20,1.20,.38,0.),
    ),
    "hub": (
        Site("town_roadside_kit",7.35,41.25,.70,.46,pi),
        Site("fair_route_crate",15.95,41.18,.57,.56,pi),
        Site("mill_tie_off",28.40,39.28,.65,.52,pi),
        Site("quarry_survey_case",44.14,42.79,.71,.49,pi),
        Site("tower_service_valve",21.89,44.69,.59,.63,None,(21.55,45.70,-.5,1.25,.50,"copper")),
        Site("shed_tool_tray",29.98,44.06,.83,.60,0.),
        Site("shed_spare_screen",32.58,43.41,.92,.82,0.),
        Site("culvert_catch_rack",34.37,48.69,.45,.53,0.,(35.18,49.76,.04,.91,.40,"silt")),
    ),
}


def install(world, chapter):
    from campaign import Billboard
    from engine import GroundMark
    from level_hickston import TILE

    sites = SITES[chapter]+(SITES["hub"] if chapter=="hickston" else ())
    world.billboards += tuple(Billboard(site.x,site.y,site.image,site.height,site.z,plane=site.plane)
                              for site in sites)
    marks = []
    for site in sites:
        if site.wear:
            x,y,heading,length,width,kind = site.wear
            marks.append(GroundMark(x,y,world.elevation(x,y)+.003,heading,length,width,f"detail_wear_{kind}"))
    world.dress_marks = tuple(marks)
    surfaces = SURFACES[chapter]+(SURFACES["hub"] if chapter=="hickston" else ())
    x = (world.walls[:,0]+world.walls[:,2])*.5
    y = (world.walls[:,1]+world.walls[:,3])*.5
    for finish in surfaces:
        left,top,right,bottom = finish.bounds
        rows = ((world.walls[:,4]==TILE[finish.base])
                & (x>=left)&(x<=right)&(y>=top)&(y<=bottom))
        if finish.name=="bar_wainscot":
            rows &= ~((x==7.)&(y==18.5))
        world.walls[rows,4] = TILE[finish.tile]

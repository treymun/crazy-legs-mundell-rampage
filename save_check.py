import os, json, tempfile, pathlib
os.environ["SDL_VIDEODRIVER"]="dummy"; os.environ["SDL_AUDIODRIVER"]="dummy"
import session_store as ss
from main import Desktop
from game import Controls
from weapons import TEAT, COW
d=Desktop(smoke=True)
for lvl in ("hickston","fair","sawmill","quarry"):
    d.start(lvl,replay=True) if lvl!="hickston" else d.start(lvl); g=d.game
    g.armory.owned[TEAT]=True; g.armory.loaded[TEAT]=20; g.inventory["whiskey"]=2
    for _ in range(30): g.tick(1/60,Controls())
    g.hit_scenery(next(p for p in g.world.scenery if p.id.startswith("x2")))
    tmp=pathlib.Path(tempfile.mkdtemp())/"s.json"; ss.save(g,tmp)
    g2=ss.read(tmp,d.make_game,expected_replay=g.replay)
    assert g2.armory.owned[TEAT] and g2.inventory["whiskey"]==2 and len(g2.scenery_spent)>=1, lvl
    # old-format: strip new weapon slots and items
    doc=json.loads(tmp.read_text()); 
    for k in ("owned","loaded","reserve"): doc["armory"][k]=doc["armory"][k][:12]
    for n in ("whiskey","cowpie"): doc["inventory"].pop(n,None)
    tmp.write_text(json.dumps(doc))
    g3=ss.read(tmp,d.make_game,expected_replay=g.replay); assert len(g3.armory.owned)==16
    print(lvl,"save/load OK, old-format migrates OK, scenery spent restored:",len(g2.scenery_spent))


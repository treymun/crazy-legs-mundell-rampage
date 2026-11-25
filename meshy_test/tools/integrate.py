import json, shutil, sys
S, G = sys.argv[1], sys.argv[2]
A = G + "/../assets/art"
dims = {"enemy": (1.096, 0.927, 1.644), "hog": (0.515, 1.38, 0.933), "tractor": (1.473, 2.421, 1.904)}
pics = {"enemy": "billy_0.png", "hog": "hog_0.png", "tractor": "town_tractor.png"}
mj = json.load(open(G + "/assets3d/props/meshes.json"))
for n, (w, d, h) in dims.items():
    name = "meshy_" + n
    shutil.copy(f"{S}/game/{n}_mesh.glb", f"{G}/assets3d/props/{name}.glb")
    mj[name] = [w, d, h, 512.0, h]
    shutil.copy(f"{A}/{pics[n]}", f"{A}/town_{name}.png")
    open(f"{G}/scenes/props/{name}.tscn", "w").write(f'''[gd_scene format=3]

[ext_resource type="Script" path="res://src/view3d/prop_view.gd" id="1_a"]
[ext_resource type="PackedScene" path="res://assets3d/props/{name}.glb" id="2_b"]

[node name="{name}" type="Node3D"]
script = ExtResource("1_a")
prop = "{name}"

[node name="Model" parent="." instance=ExtResource("2_b")]
''')
json.dump(mj, open(G + "/assets3d/props/meshes.json", "w"), indent="\t")
lv = json.load(open(G + "/data/grainyard.json"))
def board(img, x, y, h, plane):
    return {"x": x, "y": y, "image": img, "height": h, "z": 0, "signal": "", "glow": False, "plane": plane, "back": ""}
lv["billboards"] += [
    board("town_meshy_enemy", 47.2, 9.5, 1.644, 0.0),
    board("town_meshy_hog", 50.0, 9.6, 0.933, -0.5),
    board("town_meshy_tractor", 54.5, 4.8, 1.904, None),
]
json.dump(lv, open(G + "/data/grainyard.json", "w"))
print("ok")

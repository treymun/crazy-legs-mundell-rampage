"""Write a kind's Meshy request bodies from meshy/kinds/prompts.json.

    python meshy/tools/make_requests.py <kind>
"""
import json
import os
import sys

from PIL import Image

kind = sys.argv[1]
P = json.load(open("meshy/kinds/prompts.json", encoding="utf-8"))[kind]
SP = os.path.abspath("..")
ref_dir = os.path.join(SP, "meshy-work", "meshyref")
os.makedirs(ref_dir, exist_ok=True)
# References: the current model's front at its standing key, and its cel.
front = Image.open(os.path.join(SP, "meshy-work", "ref", kind + "_front.png")).convert("RGB")
front.save(os.path.join(ref_dir, kind + "_front.png"))
# ("refs": "cel" - the cel alone: the owner's rule of 2026-11-26, a natural
# body in the theme rather than a copy of the old model's proportions)
refs = [] if P.get("refs") == "cel" else ["@file:" + os.path.join(ref_dir, kind + "_front.png")]
cel = os.path.join("assets", "art", P.get("cel", kind + "_0") + ".png")
if os.path.exists(cel):
    im = Image.open(cel).convert("RGBA")
    k = 640 // max(im.size)
    im = im.resize((im.size[0] * k, im.size[1] * k), Image.NEAREST)
    bg = Image.new("RGB", (max(im.size) + 64, max(im.size) + 64), (190, 190, 192))
    bg.paste(im, ((bg.size[0] - im.size[0]) // 2, (bg.size[1] - im.size[1]) // 2), im)
    bg.save(os.path.join(ref_dir, kind + "_cel.png"))
    refs.append("@file:" + os.path.join(ref_dir, kind + "_cel.png"))
# More references (another of the kind's concepts, for one face across
# two models: Maw and Maw bare), named in the prompt by "extra_note".
for extra in P.get("extra_refs", []):
    refs.append("@file:" + os.path.join(SP, extra))
he = "her" if P.get("she") else "his"
concept = {
    "ai_model": "nano-banana-pro",
    "prompt": (
        "Using the reference images only as the character design (the 3D figure and the small game sprite are the same "
        "character), paint a high-detail full-body character concept of this %s for a gritty 1990s Southern comedy "
        "horror first-person shooter. Keep %s design exactly: %s. Give %s real personality: %s. Caricatured but natural "
        "anatomy. Worn and grimy: dirt, sweat stains, frayed cloth. Matte, hand-painted, gritty texture detail, muted "
        "dusty colours, not glossy, not a clean modern hero render. Front view facing the camera squarely, standing "
        "straight in a relaxed A-pose: arms straight down and held slightly away from the body, hands open and EMPTY, "
        "holding nothing: no weapon, no gun, no tool, no props in the hands. Both feet planted shoulder-width apart. "
        "Plain flat light-grey studio background, soft even lighting with no cast shadows, the whole figure in frame "
        "with space around it, sharp focus, one single subject, no text, no logo, no frame."
    ) % (P["who"], he, P["design"], "her" if P.get("she") else "him", P["face"]) + P.get("extra_note", "") + (
        " Keep only the role, the outfit idea, the colours and the props of the reference; give the character a natural,"
        " well-proportioned, believable body and an appealing, clear, readable face (no blocky toy proportions, no"
        " giant ball belly, no stubby limbs). An original character, not any real person's likeness."
        if P.get("refs") == "cel" else ""),
    "reference_image_urls": refs,
    "aspect_ratio": "3:4",
}
if P.get("refs") == "cel":
    concept["prompt"] = concept["prompt"].replace(
        "(the 3D figure and the small game sprite are the same character)", "(a small low-resolution game sprite)")
model = {
    "ai_model": "latest",
    "image_url": "@file:" + os.path.join(SP, "meshy-work", "meshy_out", kind + "_concept", "image_0.png"),
    "should_texture": True,
    "enable_pbr": False,
    "topology": "triangle",
    "should_remesh": True,
    "target_polycount": 30000,
    "symmetry_mode": "auto",
    "pose_mode": P.get("pose_mode", "a-pose"),
    "texture_prompt": P["texture"],
}
rig = {"input_task_id": "@task:%s_model" % kind, "height_meters": P.get("height", 1.75)}
for name, body in (("concept", concept), ("model", model), ("rig", rig)):
    json.dump(body, open("meshy/requests/%s_%s.json" % (kind, name), "w", encoding="utf-8"), indent=1)
print("requests written for", kind)

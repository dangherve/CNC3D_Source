#!/usr/bin/env python3
"""Bake the 128x96 cameos into a TRUE-COLOUR pack for the 640x480 HUD.

WHY THIS IS NOT cameos95.py
---------------------------
cameos95.py quantises to the game's 256-colour palette and stores 8-bit indices, because
the DOS sidebar composes its cell in index space (the build clock is a lookup through the
pack's translucency table, not paint). the art is 128x96 with 6,000 to 10,700 distinct
colours per cameo, and putting it through that costs a mean per-pixel RGB error of 7.6 to
22.8. The 640 HUD's cameo buffer is already RGBA, so the palette step is avoidable there,
and it is deliberately avoided: the project moved to 16-bit with the new HUD...
downscale them to 64x48 so they fit, and keep 16-bit color."

So this writes RGBA and nothing else. The clock and the pips are still the DOS pack's,
drawn by the sidebar; see cnc_sidebar.h for how a faded pixel is told from a pip.

THE DOWNSCALE
-------------
128x96 -> 64x48 is exactly 2:1, and every output pixel is the mean of one 2x2 block
(PIL's BOX filter). No pixel is invented, no edge is resampled across, and the operation
is the same for every file. It is still a real downscale: these are NOT a 2x export of
64x48 art, which was checked -- not one of the 54 has uniform 2x2 blocks.

FORMAT
------
    "CNC3DTDR" | u32 count | count x { char key[8]; u32 w; u32 h; u8 rgba[w*h*4] }
key is the game's own buildable ident (E1, MTNK, NUKE...), NUL-padded to 8.
"""
import os, struct, sys, glob
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
ART  = os.path.join(ROOT, "art", "cameos-tdr")
OUT  = os.path.join(ROOT, "game", "cameos_tdr.pack")
W, H = 64, 48

# the filename stem -> the game's buildable key. Derived from the same MAP that
# cameos95.py uses, so the two sets stay in step; the notes are where his names differ
# from that file's.
MAP = {
    "A10": "A10", "Airstrip": "AFLD", "APC": "APC", "Artillery": "ARTY",
    "Nuclear_Strike": "ATOM", "Adv_Guard_Tower": "ATWR", "Barbed_Wire": "BARB",
    "Buggy": "BGGY", "Recon_Bike": "BIKE", "Gunboat": "BOAT", "Air_Strike": "BOMB",
    "Concrete_Wall": "BRIK", "Chain_Link": "CYCL", "Minigunner": "E1", "Grenadier": "E2",
    "Rocket_Soldier": "E3", "Flamethrower": "E4", "Chem_Warrior": "E5", "Engineer": "E6",
    "Adv_Comm_Center": "EYE", "ConYard": "FACT", "Repair_Facility": "FIX",
    "Flame_Tank": "FTNK", "Guard_Tower": "GTWR", "Turret": "GUN", "Hand_of_Nod": "HAND",
    "Harvester": "HARV", "Apache": "HELI", "Helipad": "HPAD", "Comm_Center": "HQ",
    "Mammoth_Tank": "HTNK", "Ion_Cannon": "ION",
    # the reported "Light Scout" is the Hum-vee, whose ident is JEEP.
    "Light_Scout": "JEEP",
    "Hovercraft": "LST", "Light_Tank": "LTNK", "MCV": "MCV",
    # The GDI rocket launcher's ident is MSAM, settled in cameos95.py's own notes.
    "Rocket_Launcher": "MSAM",
    "Medium_Tank": "MTNK", "Adv_Power_Plant": "NUK2", "Power_Plant": "NUKE",
    "Obelisk_of_Light": "OBLI", "Orca": "ORCA", "Refinery": "PROC", "Barracks": "PYLE",
    "Commando": "RMBO", "SAM_Site": "SAM", "Sandbags": "SBAG", "Silo": "SILO",
    "Stealth_Tank": "STNK", "Temple_of_Nod": "TMPL", "Transport": "TRAN",
    "Weapons_Factory": "WEAP", "Wood_Fence": "WOOD",
}
# Drawn, but Tiberian Dawn's sidebar has no buildable for it. Kept in the repo, left out
# of the pack, and named here so it reads as a decision rather than an oversight.
UNUSED = {"SSM_Launcher"}


def build():
    if not os.path.isdir(ART):
        sys.exit("missing art dir: %s" % ART)
    entries, seen, unknown = [], set(), []
    for path in sorted(glob.glob(os.path.join(ART, "TDR_*_Cameo.png"))):
        stem = os.path.basename(path)[4:-len("_Cameo.png")]
        if stem in UNUSED:
            continue
        key = MAP.get(stem)
        if not key:
            unknown.append(stem)
            continue
        im = Image.open(path).convert("RGBA")
        if im.size != (128, 96):
            sys.exit("%s is %dx%d, expected 128x96" % (stem, im.size[0], im.size[1]))
        im = im.resize((W, H), Image.BOX)
        entries.append((key, im.tobytes()))
        seen.add(key)
    if unknown:
        sys.exit("unmapped cameo art, add it to MAP or UNUSED: %s" % ", ".join(unknown))
    entries.sort()
    with open(OUT, "wb") as f:
        f.write(b"CNC3DTDR")
        f.write(struct.pack("<I", len(entries)))
        for key, rgba in entries:
            f.write(key.encode().ljust(8, b"\0"))
            f.write(struct.pack("<2I", W, H))
            f.write(rgba)
    print("wrote %s: %d cameos at %dx%d RGBA (%.1f MB)"
          % (OUT, len(entries), W, H, os.path.getsize(OUT) / 1048576.0))


if __name__ == "__main__":
    build()

# Cameo art, 128x96

54 PNGs, hand-drawn and delivered as
`tdr_pixel_art_128x96_final_20260818.zip` (the zip is kept beside them, unmodified, as
the delivered artefact). They are **authored source, not extracted or generated**, so
they live in the repository rather than on one machine's desktop.

## What they are

All 54 are exactly **128x96** and full colour: 6,021 to 10,735 distinct colours each,
median 8,651. They are NOT a 2x export of 64x48 art -- no file has uniform 2x2 blocks --
so halving them is a real downscale, not an undo.

## Where they are going, and what is not done

the instruction: **use them in the NEW (640x480) HUD, downscaled to 64x48, keeping the
colour.** Two notes for whoever picks this up:

* The 640 HUD's cameo buffer is already RGBA (`g_h6Cameo`, `cnc_sidebar.h`). What is NOT
  true-colour is the path that fills it: the cell is composed in 8-bit index space and
  only expanded through `cp->pal8[]` at the last step. Feeding these through it unchanged
  costs a mean per-pixel RGB error of 7.6 to 22.8 (median 11.2), which is visible.
* The reason that path is 8-bit is the **build clock**, which is not painted -- it is a
  lookup through the pack's own translucency table. Moving the cameo layer to true colour
  means making the clock an RGB operation. It is not a simple alpha blend: fitting the
  table as `dst = src*(1-a) + C*a` leaves a worst-case error of 430 out of a possible 441.
  The table is **512 bytes, not 256, and its two halves differ**, so it is two tables and
  reading it as one is the first mistake to avoid. Decode it before touching the
  compositor.

## Naming

`TDR_<Name>_Cameo.png`. All but one map onto the game keys already listed in
`tools/sidebar_redesign/cameos95.py`'s `MAP` (JEEP is the reported "Light Scout"); the extra is
`TDR_SSM_Launcher_Cameo.png`, which has no buildable key in Tiberian Dawn's sidebar.

## Status: WIRED

Baked by `tools/sidebar_redesign/cameos_tdr.py` into `game/cameos_tdr.pack` (53 of the 54;
the SSM launcher has no buildable key) and drawn by the 640 HUD in **true colour**, 64x48,
no palette step. The build clock was the thing standing in the way and it is decoded now
rather than approximated -- see `h6_clock_fade` in `game/cnc_sidebar.h`.

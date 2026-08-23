# Tier 1 gap list (what the Windows 98 build gives up)

Two render tiers. Tier 2 is the modern desktop build, Windows and
macOS, and may use shaders freely. Tier 1 is Win98 with a 3dfx Voodoo 2 through Glide:
fixed function, no shaders, no render targets, 640x480, 16-bit colour.

Tier 1 is a stretch goal rather than the platform the project ships for. It earns this
file anyway: holding the renderer to what it can do is what keeps it reachable at all,
and the discipline costs Tier 2 almost nothing.

**This file is the contract.** Any feature that cannot run on Tier 1 belongs here, with
its Win98 fallback, before it ships. A feature that is Tier 2 only and NOT listed here is
a bug, because it converts the port from a known list of compromises into a surprise.

## Current entries

| Feature | Tier 2 | Tier 1 fallback |
|---|---|---|
| Texture wrap: clamp | `GL_CLAMP_TO_EDGE` (x4 sites, plus one in `game/dosopt_gl.h`) | `GL_CLAMP`; one texel of edge bleed, acceptable |
| Texture wrap: mirror | `GL_MIRRORED_REPEAT` (x1) | pre-mirrored texture baked at pack time, `GL_REPEAT` |

## The presentation chain

The desktop-only post chain: `game/fx_gl.h`, `fx_state.h`, `fx_post.h`, `fx_panel.h`,
plus `fx_filter.h` which is not part of the chain and is listed separately below.

**The whole chain is one row, because it has one fallback: it does not run.** With
`--gfx` absent and F5 never pressed the program draws exactly the picture it drew
before any of this existed, which gate G36 measures and the other 43 gates assume. On
Tier 1 the master switch is simply never on. Nothing about the Glide backend has to
know the chain exists.

| Feature | Tier 2 | Tier 1 fallback |
|---|---|---|
| Offscreen render target (`GL_EXT_framebuffer_object`, RGBA8 + a sampleable depth texture) | the world is drawn into it and the chain reads it back | none. The Voodoo 2 has no render target; the world goes straight to the front buffer as it does today |
| GLSL 1.20 fragment programs (six of them) | shadow/occlusion/light, bright pass, blur, resolve, CRT, copy | none. Fixed function only |
| Supersampling | world drawn at up to 4x the window, box filtered down | none. The Voodoo 2 renders 640x480 and that is the resolution. Note the console DID anti-alias (RDP coverage plus the VI filter), so this is a gap on Tier 1 against the cartridge as well as against Tier 2 |
| Sun shadow map (depth-only FBO, screen-space application) | replaces the cartridge's four baked shadow mechanisms while it is on | the four baked mechanisms, which is what ships today and is what the console does |
| Bloom, ambient occlusion, dynamic light, colour grade, CRT | shader passes | none, and none of them is a fidelity loss: the cartridge has no equivalent for any of them |
| **VI output gamma** | `pow(c, gamma)` in the resolve pass | **THIS ONE IS A REAL LOSS.** `VI_CTRL = 0x0000320E` sets GAMMA_ON on the console and nothing clears it, so Tier 1 without it is less faithful than Tier 2 with it. A Glide answer exists and is not written: `grGammaCorrectionValue()` sets the hardware gamma table on a Voodoo 2. It is one call and it belongs in the Glide backend when that is built |

### `fx_filter.h`: bilinear filtering, and it is NOT a Tier 2 debt

| Feature | Tier 2 | Tier 1 answer |
|---|---|---|
| One switch flipping every texture drawn IN THE WORLD between `GL_NEAREST` and `GL_LINEAR`: the 3D pack art and terrain atlas, the DOS infantry sprites, the tiberium, the decals, the construction scaffold. **Never the UI** -- not the sidebar, cameos, fonts, cursors, pause dialog, menus or movies | `glTexParameteri` over a register of every uploaded WORLD texture; UI textures are simply never registered, so the switch has no way to reach them | **the Voodoo 2 filters bilinearly in hardware and has since 1996.** `grTexFilterMode(GR_TEXTUREFILTER_BILINEAR)` per TMU, set per texture source rather than globally. This is one of the few additions Tier 1 can simply do |

Worth recording alongside it: the console's RDP filtered its textures bilinearly, so
point sampling is OUR choice, not the cartridge's. Whichever way this switch is set
it is a decision, and the default (off, point sampled) is the one that keeps every
existing gate's pixels where they were.

## Nothing else is Tier 2 only yet

Everything currently shipped (soft shroud, DOS sprites, particle effects, turret
rotation, the sidebar, the menu, the movies and the pause dialog) runs in fixed
function OpenGL 1.1 and maps to Glide.

The movie player (`video/movieplay.c`) is one `GL_NEAREST` texture and one quad, with
the palette conversion and the fade done on the CPU exactly as the DOS original faded
the VGA palette. The pause dialog (`game/dosopt.c` + `game/dosopt_gl.h`) is one 8-bit
surface, one texture and one quad, drawn with the same `dosbar.c` primitives as the
sidebar. Neither needs anything the Voodoo 2 does not have.

## Audio (added with the sound round)

The audio engine is under the same contract and currently costs Tier 1 **nothing**,
because nothing in the mixer touches a platform API.

| Piece | Tier 2 | Tier 1 answer |
|---|---|---|
| Mixer, `.AUD` decoders, MIX reader, sound bank, theme playlist, the WAV tap | plain C89, no platform call, no C++ | the identical files, handed to a different C compiler |
| The device | `audio/audio_sdl.c`: an SDL2 callback at 22050 Hz stereo, 1024 frame buffer | **a new file with the same five functions.** A DirectSound secondary buffer or a `waveOut` double buffer, calling `mixer_render()` at the refill point; `audio_backend_lock/unlock` become a critical section, or nothing at all if the refill happens on the main loop |
| Music streaming | `cnc_audio_update()` decodes on the GAME thread and pushes into a ring the device only reads | unchanged, and it is the whole reason a Win98 backend does not have to make stdio interrupt safe |
| Decoded clip cache | 8 MB LRU cap | unchanged. The cap exists precisely for this target: decoding all 249 sounds at once is about 12 MB, which is fine on a modern machine and is not fine on Win98 |

**`audio/audio_win98.c` IS WRITTEN NOW, and it is a new file, not a
rewrite.** It implements the same six functions `audio_sdl.c` does and touches nothing
else, over `waveOut` rather than DirectSound: winmm.dll is on every Windows 98 install
as shipped, where DirectSound would add a DirectX runtime to require, detect and fall
back from, and it buys nothing when the mixer already hands the device a finished stereo
stream.

The one delicate part is the threading, and it is written down in the file: a waveOut
callback runs in an interrupt-like context where Microsoft names the only legal calls,
and `mixer_render` is not among them. So the callback does exactly one legal thing,
`SetEvent`, and a worker thread refills and re-queues the four buffers. That makes
`audio_backend_lock/unlock` a CRITICAL_SECTION around the render, which is precisely the
guarantee `SDL_LockAudioDevice` gives on the other backend.

**What is proven and what is not.** It compiles as 32-bit Windows code with `-Wall
-Wextra` and no warnings, and it links against the whole audio core with `-lwinmm`,
which is what says the seam is satisfied rather than merely typed. **It has never run on
Windows 98**, because the renderer's own Win98 and Glide port has not started, so there
is no build on that machine to hear it. CI compiles it on every push, alone, so that it
cannot rot while it waits.

**A REAL Tier 1 finding fell out of that link, and it is not about audio.** The probe
binary imports `api-ms-win-crt-*.dll`: that is the UCRT, which Homebrew's mingw-w64
links by default and which **does not exist on Windows 98**. Ubuntu's mingw-w64 (what CI
uses) is the MSVCRT variant and imports `msvcrt.dll`, which does. It is
already recorded that the two toolchains differ and that both run on Windows 11; what is
new is that the difference is load-bearing for Tier 1. **The Win98 build must be made
with the MSVCRT variant**, whichever machine makes it, and that is a toolchain decision
to settle before the port starts rather than a link error to discover during it.

## Construction animation (added with the buildup round)

The 1995 buildup pass costs Tier 1 **nothing** by construction: `dosmake.pack` sheets
are all 256x256 or smaller (the baker PAGES a long strip across several sheets rather
than exceeding the Voodoo 2 texture limit -- TMPL's 36 frames span 4 sheets), the
loader uses GL 1.1 calls only (`GL_CLAMP`, no new tokens, same audited wrap-ledger
reasoning as the infantry loader), and the draw is one alpha-tested quad per building
under construction. The only Tier 1 cost is one texture bind per constructing
building per frame, on a 5-second one-shot animation.

## Wave 4: water, per-object shroud, health bars

Everything in this round is fixed-function and lands inside the Tier 1 contract. The one
item that adds a hardware requirement is the water, and the Voodoo 2 is the machine it was
designed for.

| Piece | Tier 2 | Tier 1 answer |
|---|---|---|
| **Soft decal edges** (`decal_soft`) | A box blur of the smudge sheet's ALPHA channel at load, per frame cell, then `GL_SRC_ALPHA / GL_ONE_MINUS_SRC_ALPHA` with a floor-level alpha test instead of the 0.5 test | **NATIVE, and it is not even a compromise.** The blur is a CPU pass over 270 KB at load, which the Pentium-class target does once. The draw needs `grAlphaBlendFunction(GR_BLEND_SRC_ALPHA, GR_BLEND_ONE_MINUS_SRC_ALPHA)` plus `grAlphaTestFunction(GR_CMP_GREATER)` at a low reference, which is one state change and exactly what the console's own FORCE_BL composite does. The alpha test path is kept for `decal_soft 0` and is the cheaper of the two, so a Voodoo 2 that wants the frames back can have the cartridge's hard edge for free. **This is a DEVIATION, not a fidelity feature:** the console draws these hard, and 0 restores it byte for byte |
| **Water surface** | Two texture units, both `GL_MODULATE`, primary colour `(1,1,1,170/255)`, one `GL_SRC_ALPHA / GL_ONE_MINUS_SRC_ALPHA` blend, depth write off, `GL_LEQUAL` | **Native.** The Voodoo 2 has TWO TMUs: `grTexCombine` MODULATE on TMU0 against TMU1's output, iterated (Gouraud) alpha, `grAlphaBlendFunction(SRC_ALPHA, ONE_MINUS_SRC_ALPHA)`, `grDepthMask(FXFALSE)`, `GR_CMP_LEQUAL`. This is the card's home ground rather than a compromise. Watch item only: 16-bit colour will band the WATER1 x WATER2 product slightly, which is a 16-bit fact and not a feature loss. **If a single-TMU fallback is ever needed it is NOT the console's lerp** and must be registered as a deviation, not shipped quietly. |
| **Water UV warp** | Two `sinf` and two `cosf` per water corner per frame, on the CPU | Unchanged. SCG01EA has 389 water cells, so under 1600 corners per frame; a Pentium-class box handles that. If it is ever tight, a 256-entry sine table matches the console's own quantisation exactly (it truncates S/T to s16, i.e. 1/96 of a repeat). |
| **Seabed (BOTTOM.IMG)** | One extra opaque textured pass over water cells only, single TMU, `GL_REPEAT` on a 32x32 tile | Unchanged, and it is CHEAPER than the water pass above it. |
| **Coincident water/terrain depth** | Depth write off plus `GL_LEQUAL` on surfaces that share vertices | Same on Glide. Watch item: 16-bit Z precision at 640x480 on coincident surfaces. The console faces the identical situation and solves it the identical way, so if it sparkles the answer is a depth-range tweak, **not** `glPolygonOffset`, which Glide does not have. |
| **Per-object shroud darkening** | One bilinear lookup per vertex, subtracted from the vertex colour before submission | Unchanged: this is per-VERTEX COLOUR arithmetic done on the CPU, which is exactly what fixed function can consume. No shader, no second pass, no render target. The only Tier 1 cost is the lookup itself, and it is four array reads and a lerp. |
| **Vehicle washboard lean** | Two `sinf` per drawn vehicle per frame plus a 3x3 rotate folded into the existing per-vertex transform | Unchanged. Pure CPU arithmetic on geometry we already transform by hand. |
| **World-space health bars** | Two untextured quads per bar, depth tested and written, no blend | Unchanged, and strictly cheaper than the screen-space overlay it replaced (which needed an ortho projection switch per frame). |

Nothing in this round introduced a shader, a render target, a new GL token or a texture
larger than 256x256.

## Wave 5: the MCV deploy rig

Nothing here introduces a shader, a render target, a new GL token or a texture larger than
256x256. The rig rides the PKB node-animation path that already existed for the idle
clips, so its Tier 1 answer is that path's answer.

| Piece | Tier 2 | Tier 1 answer |
|---|---|---|
| **Per-node animated draw (`draw_mesh` animT)** | Per drawn part, one lerp between two baked 3x4 matrices, then a 3x4 multiply per vertex. Immediate-mode `glVertex3f`, no VBO, no shader | **Unchanged.** The vertices are transformed on the CPU already, in the same loop that applies facing, mount and lean; the animation is one more 3x4 before `grDrawTriangle`. Cost is bounded by the rig's 278 triangles and it draws for at most one object at a time. |
| **Baked clip storage** | 102 frames x 21 parts x 12 floats = 103 KB of `float` per pack, resident | **Watch item, not a blocker.** A Win98-era machine has this, but it is the largest single animation block in the pack and a 16 MB build should measure the pack's total resident size before adding more one-shot rigs. Halving it to `short` fixed-point is available and was NOT done, because nothing needs it yet. |
| **The rig REPLACES the yard's mesh** | One `draw_mesh` instead of another, same three passes | Unchanged: strictly fewer triangles than the finished Construction Yard it stands in for. |

## Wave 5: the cursor animations

Nothing here introduces a shader, a render target, a new GL token or a texture larger than
256x256. The ten animated cursor states reach the screen through two paths that already
had Tier 1 answers, so this section is mostly a statement that nothing new was spent.

| Piece | Tier 2 | Tier 1 answer |
|---|---|---|
| **Animated cursor nodes (codes 0x03, 0x04, 0x06, 0x08, 0x09)** | The PKB node-animation path: one lerp between two baked 3x4 matrices per part, then a 3x4 multiply per vertex, immediate mode | **Unchanged**, and it is the cheapest user that path will ever have: the whole cursor is 5 parts and at most 65 triangles, drawn once per frame. The clock is an integer multiply and a modulo. |
| **Baked cursor clips** | 100 frames x 5 parts x 12 floats = 24 KB per animated cursor, 5 of them, 120 KB per pack resident | **Watch item, not a blocker**, and it is the same watch item the MCV rig already raised: the packs' total resident animation is now about 230 KB. The same `short` fixed-point halving is available and again was not done because nothing needs it. |
| **Flipbook cursors (0x0A, 0x0B) as per-frame mesh variants** | 7 extra meshes (4 x 124 and 3 x 22 triangles) and 7 extra textures, at most 8x8 and 2x6 texels | **Native, and deliberately so.** The alternative -- rebinding a texture mid-mesh from a per-frame index table -- would also have worked on Glide, but the variant meshes need NO new mechanism at all: the renderer picks a mesh index and draws it, which is what it does for every other model. The textures are 256 and 24 bytes of RGBA each; `grTexDownloadMipMap` will not notice them. |
| **`cursor3dstate` / `cursor3danim` script verbs** | Test-only, no draw cost | Not shipped behaviour: they change which of the cartridge's own 20 state rows is used, and both default to the engine's answer. No Tier 1 surface at all. |


## Wave 5: the terrain CM tint layer

**This is the one place so far where the Voodoo 2 is BETTER than desktop GL fixed
function, and the answer is that it can express the console's combiner exactly, in one
TMU and one pass.** That is worth stating plainly because the reflex on reading
"subtract before modulate" is to assume a Tier 1 gap, and there is none here.

The cartridge's ground combiner (G_SETCOMBINE 0xFC15982B / 0x4433FFFF at ROM 0x19A5AC,
G_CYC_1CYCLE at ROM 0x19C3C0) is, per channel:

```
out = clamp8( ((TEXEL0 - tint) * lit + 0x80) >> 8 )
```

tint = the vertex RGB (the CM layer), lit = the vertex ALPHA (the per-corner light).

**It cannot fold into the vertex colour.** `GL_MODULATE` gives `T * C`, and matching the
console needs `C = lit/256 - (tint*lit)/(256*T)`, a function of the TEXEL. The subtracted
term is an offset, not a scale, so no vertex colour reproduces it on more than one texel
value. Both tiers therefore need a combine form, not a colour.

| Piece | Tier 2 | Tier 1 answer |
|---|---|---|
| **The subtract-then-modulate itself** | TWO texture env stages. Unit 0 `GL_COMBINE` / `GL_SUBTRACT(TEXTURE, PRIMARY_COLOR)`; unit 1 `GL_COMBINE` / `GL_MODULATE(PREVIOUS, PRIMARY_COLOR` with `GL_SRC_ALPHA` as operand 1`)`. Unit 1 samples nothing and is bound to the same atlas only because an env stage must be enabled to apply. New GL tokens: `GL_COMBINE`, `GL_SUBTRACT`, `GL_PREVIOUS`, `GL_PRIMARY_COLOR`, `GL_SOURCE0/1_RGB`, `GL_OPERAND0/1_RGB`, `GL_COMBINE_RGB/ALPHA`, `GL_SOURCE0_ALPHA`, `GL_OPERAND0_ALPHA` (GL 1.3 core / `ARB_texture_env_combine`) | **NATIVE, exactly, in ONE TMU.** Glide's colour combine has the form as a first-class function: `grColorCombine(GR_COMBINE_FUNCTION_SCALE_OTHER_MINUS_LOCAL, GR_COMBINE_FACTOR_LOCAL_ALPHA, GR_COMBINE_LOCAL_ITERATED, GR_COMBINE_OTHER_TEXTURE, FXFALSE)` = `(texture - iterated_rgb) * iterated_alpha`, which IS the cartridge's arm, with the same clamp at the combine output. The Gouraud vertex carries tint in RGB and light in alpha exactly as it does on GL. **So Tier 1 is one pass and one TMU where Tier 2 needs two stages, and TMU1 stays free for the water.** |
| **The alpha lane (the atlas water hole)** | Both stages `GL_REPLACE` the alpha from the texel, so the existing `glAlphaFunc(GL_GREATER, 0.5)` still cuts the river out of the ground | `grAlphaCombine(GR_COMBINE_FUNCTION_LOCAL, ..., GR_COMBINE_LOCAL_NONE, GR_COMBINE_OTHER_TEXTURE, FXFALSE)` plus `grAlphaTestFunction(GR_CMP_GREATER)` / `grAlphaTestReferenceValue(128)`. The vertex alpha is the LIGHT here and must not reach the alpha test, on either tier. |
| **The CM data itself** | 4225 u16 in the pack (8450 bytes per pack) plus a 65x65x3 byte precomputed grid, built once at load with the light | **Unchanged and negligible**: 8 KB in the pack, 12 KB resident, no per-frame arithmetic at all. |
| **Cost when the layer is a no-op** | `terrain_tint_live()` falls back to the single-stage `GL_MODULATE` when the pack has no CM block or the scaled tint is zero everywhere (CMFLAT scenarios), so those maps pay nothing | Same branch, same reasoning. |

**The one deviation, and it is a rounding one on BOTH tiers.** The RDP divides by 256
with a `+0x80` round; GL's modulate divides by 255, and Glide's combine unit likewise
works in 1/255. So a terrain pixel can come out one level brighter than the console's.
Measured by the `cmcombine` script verb against read-back pixels over 180
(texel, tint, lit) triples: **146 exact, 34 one level brighter, 0 darker.** That is the
signature of the divide and nothing else. It is not new -- the plain modulate this
replaced carried the identical /255 -- and it is recorded as a known gap rather
than corrected, because pre-scaling the vertex alpha by 255/256 would move every terrain
pixel that already exists for a sub-level gain.

**Not built, and it is a Tier 1 item too when it is:** the cartridge's SEABED pass uses
the SIBLING combiner arm (ROM 0x19A590, `(TEXEL0 - 0) * SHADE_ALPHA + SHADE`), i.e. it
ADDS the same tint to the sea floor. On Glide that is
`GR_COMBINE_FUNCTION_SCALE_OTHER_ADD_LOCAL` with the same factor, so it is equally
native when someone builds it. Left open deliberately.

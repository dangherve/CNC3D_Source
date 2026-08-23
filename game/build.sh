#!/bin/sh
# CNC3D renderer build (macOS). Absolute brain path so the workspace can live anywhere.
set -e
cd "$(dirname "$0")"

# THE OLDEST macOS THIS BINARY RUNS ON. Without it clang stamps LC_BUILD_VERSION minos
# with whatever SDK it finds (whatever is installed), and dyld refuses a Mach-O whose minos
# is newer than the running system, so the build is rejected on every Mac below macOS 26
# before main() runs. tools/mac/deployment-target.sh carries the full account and the
# reason the floor is 14.0 rather than lower. Sourced, so there is one number.
. ../tools/mac/deployment-target.sh

# THE BUILD NUMBER, regenerated before anything compiles. tools/version.sh reads the
# VERSION file at the repo root and writes game/cnc3d_build.h; nothing else in the tree
# is allowed to carry a version string, so there is no second copy to forget to bump.
# tools/release.sh has already written the header with the bare release number by
# the time it calls this, and regenerating it here would stamp the binary
# "+sha-dirty" for a build that is about to become the tag.
if [ -z "$CNC3D_SKIP_VERSION_HEADER" ]; then
    sh "../tools/version.sh" --header "../game/cnc3d_build.h"
fi

# The old ROOT pointed at a temporary folder that the OS cleans; the checkout now
# lives in the repo (brain/vanilla, gitignored). Fallback kept for odd layouts.
ROOT=..
HDR=""
for c in "$ROOT/brain/vanilla/tiberiandawn" ../brain/vanilla/tiberiandawn ../../../brain/vanilla/tiberiandawn; do
    [ -f "$c/dllinterface.h" ] && HDR="$c" && break
done
[ -n "$HDR" ] || { echo "cannot find dllinterface.h" >&2; exit 1; }

# dosbar.c is plain C89 with no GL and no SDL in it: it rasterises the 1995 MS-DOS
# sidebar into an 8-bit surface and nothing else. Compiled separately so it stays that
# way and so the Win98 build can hand it to a different C compiler unchanged.
cc -std=c89 -O2 -g -c dosbar.c -o dosbar.o
cc -std=c89 -O2 -g -c dossave.c -o dossave.o

# hud640.c is the 640x480 replacement sidebar. Same rule as dosbar.c: plain C89, no GL,
# no SDL, so the Win98 build takes it unchanged.
cc -std=c89 -O2 -g -c hud640.c -o hud640.o

# The 1995 in-game Options dialog. Same rule as dosbar.c: plain C89, no GL, no SDL,
# it rasterises into an 8-bit surface and nothing else.
cc -std=c89 -O2 -g -c dosopt.c -o dosopt.o

# gate_optlayout MEASURES that dialog's geometry, and it is a separate binary precisely
# BECAUSE of the rule above: with no SDL and no GL in dosopt.c there is nothing to open a
# window for, so the whole layout can be interrogated headlessly in milliseconds. It
# exists because the suite could not see this dialog at all -- gates.sh claimed G13
# covered it, and G13 measures no rectangle -- while reports were coming in about two geometry bugs
# in it. See the header of gate_optlayout.c.
#
# It is a BUILD PRODUCT and stays out of git (.gitignore), like every other binary here.
# It links only dosopt.o and dosbar.o; -lz is dosbar's pack reader.
cc -std=c89 -O2 -g -o gate_optlayout gate_optlayout.c dosopt.o dosbar.o -lz

# The audio engine: the mixer, the 1995 .AUD decoders and the MIX reader. Same C89
# rule as dosbar.c and for the same reason. Every file here is portable C with no
# platform call in it EXCEPT audio_sdl.c, which is the device and the one file a
# Win98 backend replaces.
AUDIO="sosadpcm wsadpcm wsaud mixfile sndbank mixer sfxtable sfxname cncaudio \
       wavio audiotap audioboot"
AUDOBJ=""
for f in $AUDIO; do
    cc -std=c89 -O2 -g -c "../audio/$f.c" -o "aud_$f.o" -I../audio
    AUDOBJ="$AUDOBJ aud_$f.o"
done
cc -std=gnu89 -O2 -g -c ../audio/audio_sdl.c -o aud_sdl.o -I../audio $(sdl2-config --cflags)
AUDOBJ="$AUDOBJ aud_sdl.o"

# -headerpad_max_install_names: reserve room in the Mach-O header so the dylib paths can
# be rewritten after the link without relinking. Same flag and same reason as app/build.sh.
clang++ -std=c++14 -O2 -g \
    -fms-extensions -fdeclspec -D__int64="long long" \
    -o cnc_eyes cnc_eyes.cpp dosbar.o hud640.o dosopt.o dossave.o $AUDOBJ \
    -I"$HDR" -I../audio \
    $(sdl2-config --cflags) $(sdl2-config --libs) \
    -Wl,-headerpad_max_install_names \
    -framework OpenGL -lz

# MAKE THE BINARY LOAD SDL FROM BESIDE ITSELF, not from the build machine's Homebrew. Same
# defect and same fix as app/build.sh: the linker records an absolute Intel-Homebrew path
# that no other Mac has, so the gates binary and the shipped binary both have to be
# repointed at @executable_path. tools/bundle-sdl.sh carries the full account, including
# why SDL3 has to travel too even though otool -L never mentions it.
sh ../tools/bundle-sdl.sh . cnc_eyes

echo "built ./cnc_eyes"

#!/bin/sh
# Build the current commit and refresh the Desktop test folder.
# The packs and dylib come from LOCAL_DATA (game data is not redistributed here).
set -e
cd "$(dirname "$0")"
DEST="${1:-$HOME/CNC3D/playable}"
LOCAL_DATA="${CNC3D_DATA:-$HOME/CNC3D/data/dist-v0.3.1}"
GITDESC=$(git describe --always --dirty 2>/dev/null || echo untracked)
# tools/release.sh sets CNC3D_BUILD_ID to the number it is about to tag, because at the
# moment it builds, VERSION has been bumped and not yet committed, so git describe would
# name the artefact "-dirty" for what is about to become a clean release.
[ -n "$CNC3D_BUILD_ID" ] && GITDESC="$CNC3D_BUILD_ID"
./build.sh
(cd ../app && ./build.sh)          # the merged program: menu, movies, mission, sound
mkdir -p "$DEST"
cp cnc_eyes "$DEST/"
cp ../app/cnc3d "$DEST/"

# THE SDL LIBRARIES TRAVEL WITH THE BUILD. Earlier they did not, and every
# macOS release ever cut was unplayable on any Mac but this one: both binaries carried
# /usr/local/opt/sdl2-compat/lib/libSDL2-2.0.0.dylib as a hard load command, there was no
# LC_RPATH, and no such file was in the folder. dyld gave up before main() ran. That is
# the same class of bug as the dosdata symlink below -- the build works here and is dead
# on arrival anywhere else -- and it breaks rule 9's "A RELEASE IS PLAYABLE".
#
# Called with no binary list ON PURPOSE, so it scans the whole folder rather than the two
# files this script just copied: playable/ is what gets zipped, and anything else left in
# it (cnc_eyes_head, say) would otherwise ship still pointing at Homebrew.
sh ../tools/bundle-sdl.sh "$DEST"

cp ../menu/dosmenu.pack "$DEST/" 2>/dev/null || true
for f in SCG01EA.pack SCB01EA.pack SCG10EA.pack cameos.pack dossidebar.pack \
         dosinfantry.pack dosmake.pack efx.pack CONQUER.MIX TiberianDawn.dylib; do
  [ -f "$LOCAL_DATA/$f" ] || echo "WARNING: $f missing from $LOCAL_DATA (regenerate with the bake tools)"
done

# THE PACKS THE GAME ACTUALLY RUNS COME FROM THE BAKERY, and until recently nothing
# put them here: this script copied the binaries and left whatever .pack files happened
# to be sitting in the folder from some earlier hand copy. That is how a build can carry
# a fix in its source and not in its data, which makes the build number on the menu a
# lie. bake5.py writes into tools/bakery/game; anything newer there wins.
#
# TWO PLACES, because the bakery is not the only thing that writes a pack. bake5.py puts
# the per-scenario packs in tools/bakery/game, and the standalone bakers -- tiberium,
# smudges, the verdict banner, the DOS infantry -- write beside themselves in game/. A
# refresh that scanned only the first would ship a stale smudge.pack on a clean machine
# and nothing would say so, which is the same hole this block was written to close.
n=0
for BAKED in ../tools/bakery/game .; do
  [ -d "$BAKED" ] || continue
  for p in "$BAKED"/*.pack; do
    [ -f "$p" ] || continue
    b=$(basename "$p")
    if [ ! -f "$DEST/$b" ] || [ "$p" -nt "$DEST/$b" ]; then cp "$p" "$DEST/$b"; n=$((n+1)); fi
  done
done
echo "packs: $n refreshed"
rsync -a missions "$DEST/" 2>/dev/null || true

# THE BRAIN TRAVELS WITH THE BUILD TOO, and until recently it did not.
#
# tools/mac/build-brain-mac.sh writes TiberianDawn.dylib into game/ and, unless you pass
# it a second destination by hand, NOWHERE ELSE. This script copied binaries and packs and
# left the brain in playable/ as whatever was last hand copied. So the shipped macOS brain
# was not a product of the build; it was a product of somebody remembering.
#
# WHAT THAT COSTS, with the receipt. v0.6.0 is the release that made aircraft exist, and
# it needed BOTH halves: a renderer that knows about K_AIRCRAFT and a brain that exports
# the Aircraft heap. It shipped correct only because the brain had been hand copied
# minutes earlier. Without that copy the package would have carried the new renderer over
# a brain that emits no aircraft at all, the milestone would have shipped doing nothing,
# and every gate would still have passed -- because the gates run in playable/ against
# that same stale brain, so they would have been asking the old brain whether the new
# feature worked.
#
# Copied UNCONDITIONALLY and then ASSERTED, the same way the gate files above are: a
# refresh that silently does nothing is the failure being closed, so "it did not arrive"
# has to be fatal rather than a warning nobody reads.
if [ -f TiberianDawn.dylib ]; then
    cp TiberianDawn.dylib "$DEST/TiberianDawn.dylib"
    [ -f "$DEST/TiberianDawn.dylib" ] || {
        echo "FAILED to copy TiberianDawn.dylib into $DEST" >&2; exit 1; }
    # Same file, byte for byte. cmp rather than a timestamp: a copy that half wrote is
    # newer AND wrong, which is the one case a timestamp cannot see.
    cmp -s TiberianDawn.dylib "$DEST/TiberianDawn.dylib" || {
        echo "TiberianDawn.dylib in $DEST does not match the one in game/" >&2; exit 1; }
    echo "brain: TiberianDawn.dylib refreshed into $DEST"
else
    echo "FATAL: no TiberianDawn.dylib in game/. Run tools/mac/build-brain-mac.sh." >&2
    echo "Refusing to make a build whose brain is whatever was last copied by hand:" >&2
    echo "that is how a release ships a renderer and an engine that disagree." >&2
    exit 1
fi

# THE GATE SUITE TRAVELS WITH THE BUILD, and until recently it did not.
#
# tools/release.sh gates every release with `sh playable/gates.sh` (the gates block, the
# line that sets RUNDIR to $ROOT/playable). playable/ is ignored in full (.gitignore:25)
# and nothing here ever put a gate file in it, so playable/gates.sh and playable/gate_*.py
# were HAND-SYNCED copies of the tracked originals in game/. Two consequences, and the
# second is the quiet one:
#
#   * a fresh clone cannot cut a release at all -- there is no playable/gates.sh to run;
#   * a working copy could gate a release with a suite older than the one in git,
#     with nothing anywhere saying which one had run.
#
# G48 made that worse by hard-depending on gate_jukebox.py, so the suite in the run
# folder now needs a python file as well as the shell script.
#
# Copied UNCONDITIONALLY, not "if newer": the tracked file in game/ is the suite, and a
# hand edit made in the run folder is exactly the drift this closes. Every name below was
# checked to exist in game/ before it went on the list. Everything else the gates read
# (gate_cargo.txt, gfx_g36_*.cfg, gate_gfx_rt.txt and the rest) is WRITTEN BY gates.sh at
# run time, so it is deliberately not here.
g=0
for f in gates.sh gate_*.txt gate_*.py gate_*.sh gfx_lowsun.cfg selfplay.txt; do
  [ -f "$f" ] || continue          # a pattern that matched nothing stays literal in sh
  cp "$f" "$DEST/$f"; g=$((g+1))
done
[ -f "$DEST/gates.sh" ] || { echo "FAIL: gates.sh did not reach $DEST" >&2; exit 1; }
# gfx_lowsun.cfg by name as well as by the loop above, because it is the one gate INPUT
# that is a preset rather than a script and its absence is silent: cnc_eyes takes
# `--gfx NOSUCHFILE.cfg` without complaint (now it says so on stderr, cnc_eyes.cpp's
# --gfx branch), so G52 would measure infantry shadows under the DEFAULT 52 degree sun
# instead of the low one and still report a number.
[ -f "$DEST/gfx_lowsun.cfg" ] || { echo "FAIL: gfx_lowsun.cfg did not reach $DEST" >&2; exit 1; }
# selfplay.txt by name for the same reason, and it is the one that was actually missing:
# gates.sh reads it as `--script selfplay.txt` after the cd to RUNDIR, so G3 -- one of the
# five mandatory gates -- went red on any machine that did not happen to have a hand-copied
# one sitting in the run folder. It matched none of the patterns above because it is neither
# gate_* nor a preset.
[ -f "$DEST/selfplay.txt" ] || { echo "FAIL: selfplay.txt did not reach $DEST (G3 reads it)" >&2; exit 1; }
# gate_optlayout is a BINARY, so it matches none of the patterns above: they are .txt, .py
# and .sh. It is the pause dialog's geometry gate (G57), built by game/build.sh out of
# game/gate_optlayout.c, and it is copied and asserted BY NAME for exactly the reason
# gfx_lowsun.cfg is: a gate input whose absence would otherwise be silent. G57 is written
# to go RED rather than skip when it is not here, because a gate that could not run is not
# a gate that passed.
cp gate_optlayout "$DEST/" 2>/dev/null || true
[ -x "$DEST/gate_optlayout" ] || { echo "FAIL: gate_optlayout did not reach $DEST (G57 runs it; game/build.sh makes it)" >&2; exit 1; }
g=$((g+1))
echo "gates: $g files copied to $DEST"

# THE SOUND DATA. Without dosdata/ beside the binary the build boots, plays and is
# completely silent, and the only thing that says so is one line on stderr. The
# archives are large (SCORES.MIX alone is 54 MB), so this is a symlink into the repo's
# data/dosdata rather than a copy; a release tarball substitutes a real copy.
if [ ! -e "$DEST/dosdata" ] && [ -d ../data/dosdata ]; then
  ln -s "$(cd ../data/dosdata && pwd)" "$DEST/dosdata"
  echo "linked dosdata -> $DEST/dosdata"
fi
# EVERY MACH-O IN THE FOLDER DECLARES A macOS FLOOR THIS OLD OR OLDER. Measured 20 Aug
# 2026: cnc3d, cnc_eyes AND TiberianDawn.dylib all carried LC_BUILD_VERSION minos 26.0,
# because no build script set a deployment target and clang stamps whatever SDK it finds.
# dyld REFUSES a Mach-O whose minos is newer than the running system, so every Mac below
# macOS 26 rejected the release before main() ran -- on top of, and hiding behind, the
# SDL bundling that was supposed to make a release playable elsewhere.
#
# WHAT IS CHECKED: cnc3d, cnc_eyes and every .dylib -- which is exactly the set
# tools/mac/make-package-mac.sh ships, the two binaries by name and the libraries by the
# same *.dylib glob. Not the whole folder: playable/ is the developer's working folder
# and accumulates things that are on nobody's allow-list (cnc_eyes_head, a stale binary
# referenced by nothing, is sitting in it as this is written), and a build that refuses
# over a file that does not ship is a build that gets switched off.
#
# TiberianDawn.dylib is here for the reason the whole item exists. It is NOT built by
# this script -- tools/mac/build-brain-mac.sh builds it and copies it in -- so a hand
# copied 26.0 brain beside two fixed binaries is the exact half-fix this catches. All
# three load in one process: two out of three still refuses to launch, and merely looks
# fixed.
. ../tools/mac/deployment-target.sh
floorbad=0
for p in "$DEST/cnc3d" "$DEST/cnc_eyes" "$DEST"/*.dylib; do
  [ -f "$p" ] || continue
  MIN=$(otool -l "$p" 2>/dev/null \
        | awk '/LC_BUILD_VERSION|LC_VERSION_MIN_MACOSX/{f=1} f && /^ *(minos|version) /{print $2; exit}')
  if [ -z "$MIN" ]; then
    echo "FAIL: $(basename "$p") declares no macOS floor at all (no LC_BUILD_VERSION)." >&2
    floorbad=1; continue
  fi
  awk -v a="$MIN" -v b="$CNC3D_MACOS_MIN" 'BEGIN{
        split(a,x,"."); split(b,y,".");
        exit ((x[1]*10000+x[2]*100+x[3]) <= (y[1]*10000+y[2]*100+y[3])) ? 0 : 1 }' \
    || { echo "FAIL: $(basename "$p") declares macOS $MIN, above the $CNC3D_MACOS_MIN floor." >&2
         floorbad=1; }
done
[ "$floorbad" = "0" ] || {
  echo "" >&2
  echo "A binary that asks for a newer macOS than the one running it is refused by dyld" >&2
  echo "before main(), so this build would not launch on any Mac below that version." >&2
  echo "The renderer and the program get the floor from tools/mac/deployment-target.sh;" >&2
  echo "the brain gets it from tools/mac/build-brain-mac.sh, which is what to run if the" >&2
  echo "name above is TiberianDawn.dylib." >&2
  exit 1; }
echo "macOS floor: cnc3d, cnc_eyes and every .dylib in $DEST are $CNC3D_MACOS_MIN or older"

echo "build $GITDESC -> $DEST"
echo "$GITDESC  $(date '+%Y-%m-%d %H:%M')" >> "$DEST/BUILD-HISTORY.txt"

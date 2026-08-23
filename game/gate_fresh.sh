#!/bin/bash
# ==================================================================================
# GATE: the binaries in the run directory are NEWER than the sources they are built
# from -- BOTH of them.
#
# WHY THIS EXISTS, twice over. There are two binaries: cnc_eyes (the renderer, which
# every --script gate drives) and cnc3d (the app, which is what PLAY.command launches
# and therefore what actually ships). They share almost all of their source. It
# is trivially easy to rebuild one, verify the change with a headless run, gate it
# green, commit it -- and hand over a build where the change is not there, because
# the menu route is still running a binary from hours ago.
#
# That has now happened TWICE:
#   17 Aug, morning -- cnc3d still carried the old pack-magic check and rejected every
#                      v13 pack with "the mission failed to start". Four gates failed
#                      and I spent the diagnosis blaming the movies.
#   17 Aug, evening -- cnc3d was three hours stale, so the cursor shadow and the
#                      cursor depth fix were both absent from PLAY.command. Both were
#                      reported as regressions. They were not regressions; they
#                      were never in the binary that ran.
#
# The pixel gates cannot catch this: they all drive cnc_eyes, which is always the one
# that got rebuilt. So the check is on the FILES, not on the picture.
#
# It compares against every source that either binary is built from, not just the one
# that was edited, because the failure mode is precisely "I edited a shared header and
# only rebuilt one of them".
# ==================================================================================
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
RUNDIR="${RUNDIR:-$REPO/playable}"

newest=0
newest_name=""
for f in "$REPO"/game/*.cpp "$REPO"/game/*.h "$REPO"/app/*.cpp "$REPO"/app/*.c \
         "$REPO"/app/*.h "$REPO"/menu/*.c "$REPO"/menu/*.h "$REPO"/audio/*.c \
         "$REPO"/audio/*.h; do
    [ -f "$f" ] || continue
    t=$(stat -f %m "$f" 2>/dev/null || stat -c %Y "$f" 2>/dev/null)
    [ -n "$t" ] || continue
    if [ "$t" -gt "$newest" ]; then newest="$t"; newest_name="$f"; fi
done

fail=0
for bin in cnc_eyes cnc3d; do
    p="$RUNDIR/$bin"
    if [ ! -x "$p" ]; then
        echo "  $bin: MISSING from $RUNDIR"
        fail=1
        continue
    fi
    bt=$(stat -f %m "$p" 2>/dev/null || stat -c %Y "$p" 2>/dev/null)
    if [ "$bt" -lt "$newest" ]; then
        age=$(( (newest - bt) / 60 ))
        echo "  $bin: STALE by ${age} min -- older than $(basename "$newest_name")."
        echo "      rebuild it:  cd $REPO/$([ "$bin" = cnc3d ] && echo app || echo game) && ./build.sh && cp $bin $RUNDIR/"
        fail=1
    else
        echo "  $bin: current"
    fi
done

if [ "$fail" -eq 0 ]; then
    echo "gate_fresh: both binaries are newer than every source"
    exit 0
fi
echo "gate_fresh: a deployed binary is older than the source it is built from"
exit 1

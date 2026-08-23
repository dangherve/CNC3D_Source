#!/bin/sh
# Make a build. One command, both platforms, one number, everything pushed.
#
#   tools/release.sh              make the next build and push it
#   tools/release.sh --dry-run    do everything except commit, tag, push and publish
#   tools/release.sh --next       print what the next build number would be
#
# THE RULES THIS ENFORCES, so that they are enforced rather than remembered:
#
#  1. Every build has a number, and the number goes up by 0.0.1. It lives in VERSION,
#     it reaches the menu plate through tools/version.sh, and it becomes the git tag.
#  2. Every build is BOTH platforms of the SAME COMMIT. Never a Mac build now and a
#     Windows one later; that is project rule 4 and it is the rule this project has
#     broken most expensively.
#  3. Every build has a changelog entry, written BEFORE the build, in the existing
#     format. This script refuses to run without one, because a build nobody wrote
#     down is a build nobody can tell apart from the last one.
#  4. Everything is pushed. Not just the commit: this refuses to run with an untracked
#     file in the tree, because the project is worked from more than one checkout and
#     anything that exists in only one of them is work that can be lost.
#  5. The branches `windows` and `macos` are RELEASE POINTERS, not development lines.
#     Both are moved to the released commit, so checking out either on either machine
#     always gives the same gate-tested code. Work lands on main and nowhere else.
#  6. The gates must pass before anything is tagged or pushed.
set -e
cd "$(dirname "$0")/.."
ROOT=$(pwd)

# --minor cuts a MILESTONE build (0.5.9 -> 0.6.0) instead of the usual patch. It is a
# flag rather than something the script works out, because whether a round is a milestone
# is a judgement about what shipped and no version string carries that.
DRY=0
MINOR=0
NEXTONLY=0
for a in "$@"; do
    case "$a" in
    --dry-run) DRY=1 ;;
    --minor)   MINOR=1 ;;
    --next)    NEXTONLY=1 ;;
    esac
done

VERB=--next
[ "$MINOR" = "1" ] && VERB=--next-minor
if [ "$NEXTONLY" = "1" ]; then tools/version.sh "$VERB"; exit 0; fi

NEXT=$(tools/version.sh "$VERB")
TAG="v$NEXT"
say() { printf '\n== %s\n' "$*"; }
die() { printf '\nRELEASE REFUSED: %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------- 1. the tree is sane
say "checks"
BR=$(git rev-parse --abbrev-ref HEAD)
[ "$BR" = "main" ] || die "you are on '$BR'. Work lands on main; windows and macos are
       release pointers this script moves for you, and committing on them by hand is how
       the checkouts drift apart."

git diff --quiet || die "there are uncommitted changes. A build is made from a commit, so
       commit the work first: the build number on the menu would otherwise say -dirty and
       the tag would point at something is not in hand."
git diff --cached --quiet || die "there are staged but uncommitted changes."

UNTRACKED=$(git ls-files --others --exclude-standard)
[ -z "$UNTRACKED" ] || die "untracked files present, and rule 4 says everything is pushed:
$(echo "$UNTRACKED" | sed 's/^/       /')
       Commit them, or add them to .gitignore if a command in this repo rebuilds them."

git fetch -q origin
LOCAL=$(git rev-parse HEAD); REMOTE=$(git rev-parse origin/main)
BASE=$(git merge-base HEAD origin/main)
[ "$LOCAL" = "$REMOTE" ] || { [ "$REMOTE" = "$BASE" ] || die "origin/main has commits you do
       not have. Rebase and re-run the gates on the combined tree before releasing."; }

git rev-parse -q --verify "refs/tags/$TAG" >/dev/null && die "tag $TAG already exists."

# ---------------------------------------------------------------- 2. the changelog
if ! grep -q "^## .*v$NEXT" docs/CHANGELOG.md; then
    die "docs/CHANGELOG.md has no entry for v$NEXT.

       Every build gets one, in the format the file already uses, and SHORT is the rule:
       a heading, category headings, bullets, nothing else.

           ## C&C 3D v$NEXT \"Some Name\" ($(date '+%Y-%m-%d'))

           ### New features

           - one line per item, saying WHAT changed, not why or how

           ### Bugs fixed

           - ...

       Categories in order, only the ones that apply: New features, Improvements,
       Performance, Platforms and builds, Bugs fixed. No prose paragraphs, no
       'Covers up to', no known-issues section; gaps are recorded separately, not here.

       Write it first. It is the only record of what changed between two builds, and it
       is what announces the build."
fi
say "changelog entry for v$NEXT found"

# THE OTHER HALF OF THE SAME RULE: an EARLIER build whose entry went into the changelog and
# whose release never appeared on GitHub. Cutting a new build on top of that buries it, and
# the changelog goes on naming versions nobody can download. The check passes while v$NEXT
# itself is written-but-not-yet-cut, which is the state this script requires two checks
# above; it fails only on a version older than the one in VERSION.
tools/changelog-check.sh || die "changelog and GitHub have drifted (above). A build updates
       the changelog AND the builds on GitHub, so the older gap gets closed before a new
       build is stacked on top of it."

# ---------------------------------------------------------------- 3. stamp the number
say "stamping $TAG"
echo "$NEXT" > VERSION
# --release, so the binaries carry the bare number rather than a sha: the very next thing
# this script does on success is commit and tag exactly this tree.
BUILDSTR=$(tools/version.sh --release)
{
    echo "/* GENERATED by tools/version.sh. Do not edit and do not commit: it is"
    echo "   rebuilt by every build script, from the VERSION file at the repo root. */"
    echo "#ifndef CNC3D_BUILD_H"
    echo "#define CNC3D_BUILD_H"
    echo "#define CNC3D_BUILD \"$BUILDSTR\""
    echo "#endif"
} > game/cnc3d_build.h

restore() {
    git checkout -q -- VERSION 2>/dev/null || true
    tools/version.sh --header game/cnc3d_build.h
}

# ---------------------------------------------------------------- 4. build both halves
say "building macOS"
CNC3D_SKIP_VERSION_HEADER=1 CNC3D_BUILD_ID="$TAG" game/make-build.sh || { restore; die "the macOS build failed."; }

say "building Windows"
# A dry run still COMPILES the Windows half, because "does it build" is the whole point;
# it just does not spend minutes zipping 845 MB of game data nobody is going to send.
WINARG=""
[ "$DRY" = "1" ] && WINARG="--no-zip"
CNC3D_SKIP_VERSION_HEADER=1 CNC3D_BUILD_ID="$TAG" tools/win/make-build-win.sh $WINARG || { restore; die "the Windows build failed.
       Both platforms come from one commit, so a Windows failure stops the release rather
       than shipping half of it."; }

# ---------------------------------------------------------------- 5. the gates
say "gates"
GLOG=$(mktemp)
if ! RUNDIR="$ROOT/playable" sh playable/gates.sh "$TAG" > "$GLOG" 2>&1; then
    tail -40 "$GLOG"; restore; die "the gate suite did not finish. Log: $GLOG"
fi
TAIL=$(tail -1 "$GLOG")
echo "$TAIL"
case "$TAIL" in
*" 0 fail"*) : ;;
*) tail -40 "$GLOG"; restore; die "gates are not clean: $TAIL
       Nothing is tagged or pushed. Full log: $GLOG" ;;
esac
# The Windows binaries are cross compiled here and cannot be run, so this suite is the
# MAC half only. Said out loud rather than implied, because "the gates passed" has meant
# two different things on this project before.
say "gates green on macOS. The Windows binaries are cross compiled and UNTESTED here:
   they have to be run on Windows (the Windows build notes)."

# ---------------------------------------------------------------- 6. commit, tag, push
if [ "$DRY" = "1" ]; then
    say "dry run: not committing, tagging, pushing or publishing"
    restore
    exit 0
fi

say "committing and tagging $TAG"
git add VERSION docs/CHANGELOG.md
git commit -q -m "Build $TAG

Both platforms from this commit. The gates were run on the macOS half before the tag
went on; the Windows half is cross compiled and has to be run on Windows."
git tag -a "$TAG" -m "CNC3D $TAG"

# CAPTURE THE RELEASED COMMIT NOW, and never read HEAD again. On v0.5.3 the parallel
# push landed while this script was running and main moved underneath it, so the
# closing line reported a commit that was not the one released. Nothing was actually
# mispublished -- the tag and both pointers were already correct -- but a message that
# names the wrong commit is exactly the kind of thing someone later takes as evidence.
# HEAD is a moving target in a repo two agents share; RELCOMMIT is not.
RELCOMMIT=$(git rev-parse HEAD)

say "pushing main, the tag, and the two release pointers"
git push -q origin main
git push -q origin "$TAG"
# windows and macos are pointers at the released commit, so they are SET, not merged,
# and they are set to the SHA captured above rather than to whatever HEAD says by now.
git branch -f macos   "$RELCOMMIT"
git branch -f windows "$RELCOMMIT"
git push -q -f origin macos:macos
git push -q -f origin windows:windows

# ---------------------------------------------------------------- 7. publish the builds
# WHAT GETS ATTACHED: THE PLAYABLE BUILDS, DATA AND ALL. (a project rule,
# after v0.5.1 first went out with binaries only.) A release that cannot be played is not
# a build, it is a source archive with extra steps. Both platforms ship the whole folder:
# unzip it and double-click, with nothing to fetch and nothing to bake.
#
# The small binary-only zips go up ALONGSIDE them, because they are what you want when
# you already have the folder: 13 MB instead of 450, unzipped over the top, data untouched.
#
# THE MAC PACKAGE IS BUILT FROM AN ALLOW-LIST, in tools/mac/make-package-mac.sh, which
# sits beside the Windows script it is modelled on so the two read the same way. Until
# this step was
#
#     cp -RL playable "$STAGEDIR/$MACFULLNAME"
#     rm -f  "$STAGEDIR/$MACFULLNAME"/BUILD-HISTORY.txt
#
# which is the entire developer working folder minus exactly one file. So every release
# also carried the gate suite, 433 proof screenshots (255 MB in shots/), three audio
# captures, a save/load test directory, ~40 loose proof PNGs and the hand-tuned
# presentation preset. The published macOS zip was 748 MB against Windows' 511 MB, and
# the 237 MB difference was almost exactly shots/. Subtraction cannot fix that: the next
# new kind of artefact is not on the exclude list and nobody finds out.
#
# WHAT cp -RL WAS FOR IS NOT LOST. playable/dosdata is a SYMLINK into the repo so that a
# local test folder does not carry a second 527 MB copy of the 1995 discs. Archive that
# link AS a link and it expands on the other machine as a dangling pointer, after which
# the game boots, runs, and is silent, with one line on stderr to say so. The packaging
# script rsyncs -L and then ASSERTS that dosdata arrived as a real directory holding
# SCORES.MIX, so the dereferencing is now checked rather than merely intended.
say "packaging the playable builds, data and all"
BINDIR=$(mktemp -d)
STAGEDIR=$(mktemp -d)
cleanup_pkg() { rm -rf "$STAGEDIR"; }

MACFULLNAME="CNC3D-macos-$TAG"
tools/mac/make-package-mac.sh "$STAGEDIR/$MACFULLNAME" || { cleanup_pkg; die "the macOS
       package could not be assembled. It is an allow-list and it refuses rather than
       shipping a folder with a piece of the game missing; the message above names the
       piece. Nothing has been published."; }
MACZIP="$BINDIR/$MACFULLNAME.zip"
( cd "$STAGEDIR" && zip -qrX "$MACZIP" "$MACFULLNAME" -x '*.DS_Store' ) || MACZIP=""
cleanup_pkg

# The Windows full package was already assembled and zipped by make-build-win.sh above.
WINZIP=$(ls -t "$HOME/Desktop"/CNC3D-windows-"$TAG".zip 2>/dev/null | head -1)

say "packaging the binary-only updates"
MACBINS="$BINDIR/CNC3D-macos-$TAG-bins.zip"
# THE SDL LIBRARIES ARE PART OF "THE BINARIES", and leaving them out of this zip
# reintroduces the bug the bundling fixed. From the binaries load SDL from
# @executable_path (tools/bundle-sdl.sh has the account); unzipped over a folder from an
# older release, which has no SDL beside it, they die in dyld before main() exactly as
# before, with "Library not loaded: @executable_path/libSDL2-2.0.0.dylib".
#
# THE GLOB IS EXPANDED HERE, BY THE SHELL, AND WHAT COMES OUT IS CHECKED. The first
# attempt at this handed zip the pattern in single quotes:
#
#     zip -qX "$MACBINS" cnc_eyes cnc3d TiberianDawn.dylib gates.sh 'libSDL*.dylib'
#
# and the finished zip held exactly four entries and no SDL at all. Three separate
# things have to be true for a quoted glob to work and none of them is: the shell does
# not expand a quoted word, Apple's zip 3.0 does not expand an argument either (it is
# not tar), and it treats an unmatched name as a WARNING, printing "zip warning: name
# not matched: libSDL*.dylib" and exiting 0. -q silenced the warning, 2>/dev/null threw
# away what was left, and the `|| MACBINS=` guard never fired because there was no
# failure to catch. So the zip written to close the dyld bug shipped precisely the
# binaries that still had it, and said nothing.
#
# Still globbed rather than named, because a machine that links a REAL SDL2 instead of
# sdl2-compat has no libSDL3.dylib to carry and must still be able to cut a release. But
# at least one libSDL*.dylib is demanded, because zero of them is the defect above and
# not a configuration.
# gate_optlayout rides with gates.sh, and the pairing is the point. G57 runs that binary,
# so a bins update that carried the script without it would put a gates.sh on the folder
# whose G57 goes RED for a missing binary on a folder that is perfectly fine. A false red
# costs the same as a false green here: the next person stops trusting the suite.
MACBIN_LIST="cnc_eyes cnc3d TiberianDawn.dylib gates.sh gate_optlayout"
MACBIN_SDL=$( (cd playable && ls libSDL*.dylib) 2>/dev/null || true )
[ -n "$MACBIN_SDL" ] || die "playable/ holds no libSDL*.dylib, so the binary-only update
       would carry binaries that load SDL from @executable_path with no SDL beside them.
       Unzipped over an older release folder they die in dyld before main() runs, which
       is the very bug the bundling closed. Run game/make-build.sh (it calls
       tools/bundle-sdl.sh) and re-run the publish step."
MACBIN_LIST="$MACBIN_LIST $MACBIN_SDL"
MACBIN_MISSING=""
for f in $MACBIN_LIST; do
    [ -f "playable/$f" ] || MACBIN_MISSING="$MACBIN_MISSING $f"
done
[ -z "$MACBIN_MISSING" ] || die "the binary-only update is missing:$MACBIN_MISSING
       Named files are checked here rather than left to zip, which warns about a name it
       cannot match and still exits 0, so a short zip is otherwise silent."
# NOT -q, and stderr NOT discarded. A warning from zip is the one signal that told us the
# glob had failed, and the point of this block is that it can never be swallowed again.
( cd playable && zip -X "$MACBINS" $MACBIN_LIST ) \
    || die "zip failed while packing the macOS binary-only update."
# And COUNT what landed rather than trusting the exit status, because the failure this
# replaces produced both a zip and an exit status of 0.
MACBIN_WANT=$(printf '%s\n' $MACBIN_LIST | wc -l | tr -d ' ')
MACBIN_GOT=$(unzip -Z1 "$MACBINS" 2>/dev/null | wc -l | tr -d ' ')
[ "$MACBIN_GOT" = "$MACBIN_WANT" ] || die "the macOS binary-only zip has $MACBIN_GOT
       entries and should have $MACBIN_WANT ($MACBIN_LIST). A short bins zip unzipped
       over an older release folder is how a Mac ends up with new binaries and no SDL."
echo "   bins zip: $MACBIN_GOT entries ($MACBIN_LIST)"
CNC3D_BUILD_ID="$TAG" tools/win/make-build-win.sh --bins-only >/dev/null 2>&1 || true
WINBINS=$(ls -t "$HOME/Desktop"/CNC3D-windows-"$TAG"-bins.zip 2>/dev/null | head -1)

for v in MACZIP WINZIP MACBINS WINBINS; do
    eval "f=\$$v"
    [ -n "$f" ] && [ -f "$f" ] || eval "$v=''"
done
[ -n "$MACZIP" ] || die "the macOS playable package was not produced, and a release has to
       be playable. Nothing has been published; the tag and the branches are already
       pushed, so fix the packaging and re-run just the publish step."
[ -n "$WINZIP" ] || die "the Windows playable package was not produced (expected
       $HOME/Desktop/CNC3D-windows-$TAG.zip). A release is both platforms, playable."

# THE PUBLISH IS NOT OPTIONAL, AND ITS FAILURE IS NOT A FOOTNOTE. (a project rule
# 2026: a new build updates the changelog AND the builds on GitHub, and neither half goes
# without the other.) This block used to be wrapped in `if command -v gh`, and its failure
# branch echoed one line and let the script carry on to print "$TAG is out." So there were
# three separate ways to finish a release round with the changelog naming a version nobody
# can download -- gh missing, the create failing, or a create that silently dropped an
# asset -- and all three reported success. That is the state found,
# reading the changelog, seeing v0.5.8 and finding v0.5.7 as the newest download. All
# three are hard failures now.
command -v gh >/dev/null 2>&1 || die "gh is not installed, so the builds cannot be
       published, and a changelog entry with no build on GitHub is exactly the drift this
       rule exists to stop. The tag and both branches ARE pushed, so nothing is lost:
       install gh, authenticate, and re-run the publish step."
if true; then
    say "publishing the GitHub release"
    NOTES=$(mktemp)
    # No \b here: it is a GNU regex extension that POSIX awk does not have, and the first
    # release cut with this script published EMPTY notes because of it. Plain index()
    # instead, with a guard so v0.5.1 does not also match v0.5.10.
    awk -v v="v$NEXT" '
        substr($0, 1, 3) == "## " {
            if (on) exit
            n = index($0, v)
            if (n > 0) {
                c = substr($0, n + length(v), 1)
                if (c !~ /[0-9.]/) { on = 1; buf[++nb] = $0 }
            }
            next
        }
        on { buf[++nb] = $0 }
        # The trailing blank lines and --- belong to the FILE, where they divide one entry
        # from the next. On a release page they are a stray horizontal rule under the last
        # bullet, so they are trimmed here rather than left for someone to notice. exit
        # still runs END, which is what makes the buffering safe.
        END {
            while (nb > 0 && (buf[nb] == "" || buf[nb] == "---")) nb--
            for (i = 1; i <= nb; i++) print buf[i]
        }
    ' docs/CHANGELOG.md > "$NOTES"
    [ -s "$NOTES" ] || { echo "the changelog section for v$NEXT came out empty"; exit 1; }

    # THE SOURCE OFFER, ON EVERY RELEASE. These archives carry the game logic, which is
    # GPL v3, so whoever receives the binary is entitled to the corresponding source.
    # A link in the notes is the simplest way to satisfy that, and it has to be automatic:
    # a source offer that depends on somebody remembering to paste it is not an offer.
    cat >> "$NOTES" <<'SRC'

---

**Source.** C&C 3D is free software under the GNU General Public License v3. The
complete corresponding source for this build, including the modified Tiberian Dawn
game logic, is at https://github.com/freschism3000/CNC3D_Source
SRC
    WANT=0
    for z in "$MACZIP" "$WINZIP" "$MACBINS" "$WINBINS"; do
        [ -n "$z" ] && WANT=$((WANT + 1))
    done
    gh release create "$TAG" --title "CNC3D $TAG" --notes-file "$NOTES" \
        ${MACZIP:+"$MACZIP"} ${WINZIP:+"$WINZIP"} \
        ${MACBINS:+"$MACBINS"} ${WINBINS:+"$WINBINS"} >/dev/null \
        || die "gh release create failed for $TAG. The tag and both branches are pushed,
       so the code is safe, but the changelog now names a build nobody can download. That
       is the one state this rule forbids: finish the publish before doing anything else."

    # COUNT WHAT LANDED. A create that uploads three of four zips exits 0, exactly the way
    # the short bins zip did, and the release page then looks finished while missing the
    # half someone needs. Read it back from GitHub rather than trusting the exit status.
    GOT=$(gh release view "$TAG" --json assets -q '.assets | length' 2>/dev/null || echo 0)
    [ "$GOT" = "$WANT" ] || die "the $TAG release page carries $GOT assets and should carry
       $WANT. Attach the missing ones with 'gh release upload $TAG <file>'; a release with
       a partial set of builds is a release that lies about what it is."
    echo "published $TAG: $GOT assets, both playable builds plus the binary-only updates"
fi

say "$TAG is out.
   the tag, macos and windows all point at $(git rev-parse --short "$RELCOMMIT").
   main may already be ahead of it, which is the arrangement working rather than a
   problem: the pointers name the last GATED build, not the newest commit.
   The menu plate says: C&C 3D $BUILDSTR"

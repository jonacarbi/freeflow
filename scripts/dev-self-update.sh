#!/bin/bash
# Update this dev build by merging upstream source into our local branch and
# rebuilding in place -- never by downloading a release binary over the bundle.
# Local patches survive; upstream changes come in only when they merge cleanly.
#
#   $1  pid of the running app to wait for
#   $2  path of the app bundle to rebuild and relaunch
set -uo pipefail

PID="$1"
APP="$2"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG="$REPO/build/self-update.log"
IDENTITY="Apple Development: hugoaboikonie@gmail.com (X23D6W83JV)"

export PATH="$REPO/scripts/toolshim:/usr/bin:/bin:/usr/sbin:/sbin"

mkdir -p "$REPO/build"
exec >"$LOG" 2>&1
echo "=== $(date) ==="

fail() {
    echo "FAILED: $1"
    open "$APP"                       # old build is untouched, put it back up
    osascript -e "display alert \"FreeFlow update failed\" message \"$1

See $LOG\"" >/dev/null 2>&1
    exit 1
}

cd "$REPO" || fail "repo not found"
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
[ "$BRANCH" != "HEAD" ] || fail "detached HEAD; checkout a branch first"

git diff --quiet && git diff --cached --quiet || fail "uncommitted changes in $REPO; commit them first"

git fetch origin || fail "git fetch failed"
BEFORE="$(git rev-parse HEAD)"

if ! git merge --no-edit origin/HEAD; then
    git merge --abort
    fail "upstream conflicts with local changes; nothing was applied"
fi

if [ "$BEFORE" = "$(git rev-parse HEAD)" ]; then
    echo "already up to date"
    open "$APP"
    exit 0
fi

# App must be gone before codesign rewrites its bundle.
while kill -0 "$PID" 2>/dev/null; do sleep 0.2; done

if ! make all CODESIGN_IDENTITY="$IDENTITY"; then
    git reset --hard "$BEFORE"
    make all CODESIGN_IDENTITY="$IDENTITY"
    fail "upstream build failed; rolled back to $BEFORE"
fi

BUILT="$REPO/build/$(basename "$APP")"
if [ "$BUILT" != "$APP" ]; then
    # The app usually runs from /Applications; put the new build where it lives
    # so there is only ever one FreeFlow Dev bundle.
    rm -rf "$APP" && cp -R "$BUILT" "$APP" || fail "could not install $BUILT to $APP"
fi

echo "updated $BEFORE -> $(git rev-parse HEAD)"
open "$APP"

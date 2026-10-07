#!/bin/sh
# Re-apply the mwan3 IPv6 track-source re-derive fix to a pristine mwan3 tree.
#
# Why this exists: an OpenWrt feeds update (or a fresh checkout) reverts
# files/usr/sbin/mwan3track to the upstream version, silently dropping the fix
# below. Run this script after any feeds refresh to confirm the fix is back.
#
# The script only restores the tracker; it does NOT bump PKG_RELEASE in the
# package Makefile. If you re-apply over a stored baseline that already carries
# the release bump you are fine; otherwise bump PKG_RELEASE yourself so the
# rebuilt ipkg is not silently reused.
#
# Usage:
#   ./reapply-mwan3-patch.sh                 apply into this checkout
#   ./reapply-mwan3-patch.sh --check         only verify the patch still applies
#   ./reapply-mwan3-patch.sh <tree-dir>      apply into another checkout
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PATCH="$SCRIPT_DIR/mwan3-v6-rederive-src.patch"
CHECK_ONLY=0
TARGET="$SCRIPT_DIR"
while [ $# -gt 0 ]; do
	case "$1" in
		--check) CHECK_ONLY=1 ;;
		*) TARGET="$1" ;;
	esac
	shift
done

TRACKER="$TARGET/files/usr/sbin/mwan3track"

[ -f "$TRACKER" ] || {
	echo "error: $TARGET does not look like the mwan3 package tree (missing files/usr/sbin/mwan3track)" >&2
	exit 2
}

if grep -q '^refresh_src_ip()' "$TRACKER"; then
	echo "already patched: refresh_src_ip() present in $TRACKER (nothing to do)"
	exit 0
fi

if ! git -C "$TARGET" apply --check "$PATCH"; then
	echo "error: $PATCH does not apply cleanly against $TARGET" >&2
	exit 3
fi

if [ "$CHECK_ONLY" -eq 1 ]; then
	echo "check only: $PATCH applies cleanly against $TARGET"
	exit 0
fi

git -C "$TARGET" apply "$PATCH"
echo "applied $PATCH to $TARGET"
grep -n '^refresh_src_ip()\|^track_ping()' "$TRACKER" | sed 's/^/verify: /'
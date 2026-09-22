#!/bin/sh
# capture-team-keys.sh - record what ansible/team_keys/ looks like in a fresh
# clone of this repository, and what generate_keys.sh does when it finds the
# committed public keys already in place.
#
# Runs entirely on the host, in a throwaway clone under a temporary directory.
# It creates no keys and touches nothing outside that clone.
#
# Usage: sh tools/capture-team-keys.sh [outfile]
# Default outfile: media/captures/team-keys.txt

set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/media/captures/team-keys.txt}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT INT TERM

mkdir -p "$(dirname "$OUT")"

{
    echo "=== 1. files git tracks under ansible/team_keys/"
    git -C "$ROOT" ls-files ansible/team_keys | sed 's/^/    /'

    echo
    echo "=== 2. the same directory in a fresh clone"
    git clone -q --no-hardlinks "$ROOT" "$WORK/clone"
    ls -1 "$WORK/clone/ansible/team_keys" | sed 's/^/    /'

    echo
    echo "=== 3. the key paths the users role deploys by default"
    grep -n "key_path" \
        "$WORK/clone/ansible/roles/posix_hardening_users/defaults/main.yml" \
        | sed 's/^/    /'

    echo
    echo "=== 4. generate_keys.sh run in that fresh clone"
    ( cd "$WORK/clone/ansible/team_keys" \
        && sh ./generate_keys.sh </dev/null 2>&1 ) \
        | sed 's/\x1b\[[0-9;]*m//g' \
        | grep -E "Generating|already exists|No private keys found" \
        | sed 's/^/    /'
    echo "    exit status: $?"

    echo
    echo "=== 5. private keys present in the clone afterwards"
    find "$WORK/clone/ansible/team_keys" -name '*_ed25519' -print \
        | sed 's/^/    /'
    echo "    (nothing listed above means none)"
} > "$OUT" 2>&1

echo "capture written to $OUT"
cat "$OUT"

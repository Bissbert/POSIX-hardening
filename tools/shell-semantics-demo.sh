#!/bin/sh
# shell-semantics-demo.sh - demonstrate the four POSIX shell behaviours that
# several bugs in this repository rest on, so the claims in
# docs/BUGS-FOUND.md can be checked without reading the toolkit.
#
# Each demo is self-contained and touches nothing outside its own temp dir.
# It is safe to run on a workstation; it runs inside the analysis container
# only so that the shell versions are pinned.
#
# Usage: sh tools/shell-semantics-demo.sh [outfile]
# Default outfile: media/captures/shell-semantics.txt

set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/media/captures/shell-semantics.txt}"
mkdir -p "$(dirname "$OUT")"

sh "$ROOT/tools/analysis-env.sh" build >/dev/null

{
    echo "shells under test:"
    docker run --rm posix-hardening-analysis:local sh -c '
        dash -c "echo \"  dash    \$(dpkg-query -W -f=\\\$\{Version\} dash)\"" 2>/dev/null \
            || echo "  dash    (version unavailable)"
        echo "  bash    $(bash --version | head -1)"
        echo "  busybox $(busybox | head -1)"
    '

    for shell in dash bash "busybox sh"; do
        echo
        echo "================================================================"
        echo "shell: $shell"
        echo "================================================================"

        docker run --rm -e SH="$shell" posix-hardening-analysis:local sh -c '
            run() { $SH -c "$1"; }

            echo
            echo "--- 1. a while loop fed by a pipeline runs in a subshell,"
            echo "---    so assignments made in it are lost (BUG-9b, BUG-9c)"
            run "
                n=0
                printf \"a\nb\nc\n\" | while read -r x; do n=\$((n+1)); done
                echo \"  after the loop, n=\$n (three lines were read)\"
            "

            echo
            echo "--- 2. return inside that subshell leaves the subshell,"
            echo "---    not the function (BUG-5, BUG-9a)"
            run "
                f() {
                    printf \"a\nb\n\" | while read -r x; do return 1; done
                    return 0
                }
                f && echo \"  f returned 0 although its loop returned 1\"
            "

            echo
            echo "--- 3. break 2 cannot see a loop in the parent shell (BUG-16)"
            run "
                for outer in 1 2 3; do
                    printf \"a\nb\n\" | while read -r x; do break 2; done
                    echo \"  outer iteration \$outer ran anyway\"
                done
            "

            echo
            echo "--- 4. A || B | C parses as A || (B | C), so when A succeeds"
            echo "---    the loop in C never runs (BUG-17)"
            run "
                printf \"A|1\nB|2\n\" > /tmp/s.txt
                tac /tmp/s.txt 2>/dev/null || tail -r /tmp/s.txt 2>/dev/null | while IFS=\"|\" read -r t d; do
                    echo \"  LOOP SAW: \$t \$d\"
                done
                echo \"  (no LOOP SAW line above: tac printed and the loop was skipped)\"
            "

            echo
            echo "--- 5. local is dynamically scoped: a callee that assigns the"
            echo "---    same name overwrites the callers local (BUG-15)"
            run "
                callee() { level=\"CLOBBERED\"; }
                caller() {
                    local level=\"\$1\"
                    callee
                    echo \"  caller was passed 2, and now sees level=\$level\"
                }
                caller 2
            "
        '
    done
} > "$OUT" 2>&1

echo "capture written to $OUT"
cat "$OUT"

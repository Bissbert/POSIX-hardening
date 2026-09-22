#!/bin/sh
# static-analysis.sh - reproduce every static number published in this repo.
#
# Runs the same gates as .github/workflows/ci.yml over the same file set, plus
# two counts the CI does not report (SC3043 "local is undefined in POSIX sh"
# and SC3012 "lexicographical > is undefined in POSIX sh").
#
# Requires on PATH: dash, bash, busybox, shellcheck, checkbashisms.
# tools/analysis-env.sh builds a throwaway container that has all of them.
#
# Usage: sh tools/static-analysis.sh [repo-root]
# Output: a Markdown report on stdout. Exit status is always 0; the report is
# the result, not the exit code.

set -u

ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$ROOT" || exit 1

# The file set the CI checks: lib/*.sh, scripts/*.sh and the three root scripts.
file_set() {
    for f in lib/*.sh scripts/*.sh orchestrator.sh quick-start.sh \
             emergency-rollback.sh; do
        [ -f "$f" ] && printf '%s\n' "$f"
    done
}

# Shellcheck also scans ansible/utils.
shellcheck_set() {
    file_set
    for f in ansible/utils/*.sh; do
        [ -f "$f" ] && printf '%s\n' "$f"
    done
}

have() { command -v "$1" >/dev/null 2>&1; }

TOTAL=$(file_set | wc -l | tr -d ' ')
SC_TOTAL=$(shellcheck_set | wc -l | tr -d ' ')

printf '# Static analysis report\n\n'
printf 'Generated: %s\n' "$(date -u '+%Y-%m-%d %H:%M:%SZ')"
printf 'Repository: %s\n\n' "$ROOT"

printf '## Tool versions\n\n'
printf '| Tool | Version |\n|---|---|\n'
for t in dash bash busybox shellcheck checkbashisms; do
    if have "$t"; then
        case "$t" in
            dash)    v="present (no --version)" ;;
            bash)    v=$(bash --version 2>/dev/null | head -n1) ;;
            busybox) v=$(busybox 2>&1 | head -n1) ;;
            *)       v=$("$t" --version 2>&1 | head -n1) ;;
        esac
    else
        v="NOT INSTALLED"
    fi
    printf '| %s | %s |\n' "$t" "$v"
done
printf '\n'

printf '## Syntax gates\n\n'
printf 'File set: %s files (lib/*.sh, scripts/*.sh, and the three root scripts).\n\n' "$TOTAL"
printf '| Shell | Files checked | Failures |\n|---|---|---|\n'
for spec in "dash:dash" "busybox sh:busybox" "bash:bash"; do
    cmd=${spec%%:*}
    bin=${spec##*:}
    if ! have "$bin"; then
        printf '| `%s -n` | %s | not run (%s missing) |\n' "$cmd" "$TOTAL" "$bin"
        continue
    fi
    fails=0
    file_set | while read -r f; do
        $cmd -n "$f" 2>/dev/null || printf '%s\n' "$f"
    done > /tmp/sa_fail.$$
    fails=$(wc -l < /tmp/sa_fail.$$ | tr -d ' ')
    printf '| `%s -n` | %s | %s |\n' "$cmd" "$TOTAL" "$fails"
    [ "$fails" -gt 0 ] && sed 's/^/    failed: /' /tmp/sa_fail.$$
    rm -f /tmp/sa_fail.$$
done
printf '\n'

printf '## checkbashisms\n\n'
if have checkbashisms; then
    file_set | while read -r f; do
        checkbashisms "$f" 2>&1 | grep -q . && printf '%s\n' "$f"
    done > /tmp/sa_cb.$$
    n=$(wc -l < /tmp/sa_cb.$$ | tr -d ' ')
    printf 'Files with findings: %s of %s\n\n' "$n" "$TOTAL"
    [ "$n" -gt 0 ] && sed 's/^/- /' /tmp/sa_cb.$$
    rm -f /tmp/sa_cb.$$
else
    printf 'Not run: checkbashisms missing.\n'
fi
printf '\n'

printf '## ShellCheck\n\n'
if have shellcheck; then
    # The CI gate: severity=error, shell dialect sh.
    shellcheck_set | xargs shellcheck -S error -s sh -f gcc 2>/dev/null \
        > /tmp/sa_err.$$
    nerr=$(grep -c . /tmp/sa_err.$$ 2>/dev/null); nerr=${nerr:-0}
    printf 'CI gate `shellcheck -S error -s sh` over %s files: **%s findings**\n\n' \
        "$SC_TOTAL" "$nerr"
    [ "$nerr" -gt 0 ] && sed 's/^/    /' /tmp/sa_err.$$
    rm -f /tmp/sa_err.$$

    # Below the gate: the two POSIX-dialect warnings that matter here.
    shellcheck_set | xargs shellcheck -s sh -f gcc 2>/dev/null > /tmp/sa_all.$$
    for code in SC3043 SC3012; do
        n=$(grep -c "\[$code\]" /tmp/sa_all.$$ 2>/dev/null); n=${n:-0}
        case "$code" in
            SC3043) what='`local` is undefined in POSIX sh' ;;
            SC3012) what='lexicographical `\>` is undefined in POSIX sh' ;;
        esac
        printf '### %s - %s\n\n' "$code" "$what"
        printf 'Total: %s\n\n' "$n"
        if [ "$n" -gt 0 ]; then
            printf '| File | Count |\n|---|---|\n'
            grep "\[$code\]" /tmp/sa_all.$$ | cut -d: -f1 | sort | uniq -c |
                sort -rn | while read -r c f; do
                    printf '| `%s` | %s |\n' "$f" "$c"
                done
            printf '\n'
        fi
    done
    nlib=$(grep "\[SC3043\]" /tmp/sa_all.$$ | grep -c '^lib/'); nlib=${nlib:-0}
    printf 'SC3043 occurrences under `lib/`: %s\n\n' "$nlib"
    rm -f /tmp/sa_all.$$
else
    printf 'Not run: shellcheck missing.\n\n'
fi

printf '## Repository counts\n\n'
printf '| Item | Count |\n|---|---|\n'
printf '| Numbered hardening scripts in `scripts/` | %s |\n' \
    "$(ls scripts/[0-9][0-9]-*.sh 2>/dev/null | wc -l | tr -d ' ')"
printf '| Shell libraries in `lib/` | %s |\n' \
    "$(ls lib/*.sh 2>/dev/null | wc -l | tr -d ' ')"
printf '| Entries in orchestrator SCRIPT_ORDER | %s |\n' \
    "$(sed -n '/^SCRIPT_ORDER=/,/^"$/p' orchestrator.sh | grep -c '^[0-9]*:')"
printf '| Ansible roles | %s |\n' \
    "$(ls -d ansible/roles/*/ 2>/dev/null | wc -l | tr -d ' ')"
printf '| Files tracked by git | %s |\n' \
    "$(git ls-files 2>/dev/null | wc -l | tr -d ' ')"
printf '| Shell bytes (lib + scripts + root) | %s |\n' \
    "$(file_set | xargs wc -c 2>/dev/null | tail -n1 | awk '{print $1}')"

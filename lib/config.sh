#!/bin/sh
# POSIX Shell Server Hardening Toolkit
# lib/config.sh - Configuration loading
#
# Settings are resolved in this order, first wins:
#   1. command-line flags (the orchestrator exports them before loading)
#   2. the environment
#   3. config/defaults.conf
#   4. the defaults in lib/common.sh and lib/rollback.sh
#
# Source this before lib/common.sh, which makes most settings read-only.
# It has no dependencies and does not enable set -e.

# load_config FILE
# Sources FILE, but every variable FILE assigns that already had a non-empty
# value keeps that value. An empty value in the environment does not count as
# set, so an accidentally exported empty variable cannot blank a setting.
# Works on any config file, including ones generated from older templates or
# by the Ansible roles, because the override is applied here and not in the
# file.
load_config() {
    _lc_file="$1"
    [ -f "$_lc_file" ] || return 0

    _lc_names=$(sed -n 's/^[[:space:]]*\(export[[:space:]][[:space:]]*\)\{0,1\}\([A-Za-z_][A-Za-z0-9_]*\)=.*/\2/p' "$_lc_file" | sort -u)

    _lc_kept=""
    for _lc_name in $_lc_names; do
        case "$_lc_name" in _lc_*) continue ;; esac
        eval "_lc_val=\${$_lc_name-}"
        if [ -n "$_lc_val" ]; then
            eval "_lc_env_$_lc_name=\$_lc_val"
            _lc_kept="$_lc_kept $_lc_name"
        fi
    done

    # shellcheck disable=SC1090
    . "$_lc_file"

    for _lc_name in $_lc_kept; do
        eval "$_lc_name=\$_lc_env_$_lc_name"
        unset "_lc_env_$_lc_name"
    done

    unset _lc_file _lc_names _lc_kept _lc_name _lc_val
    return 0
}

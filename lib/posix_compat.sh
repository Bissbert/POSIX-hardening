#!/bin/sh
# POSIX Compatibility Layer
# Provides portable alternatives to GNU-specific commands
# Version: 1.0.0
#
# Usage: source this file at the beginning of scripts that need POSIX portability
#   . "${SCRIPT_DIR}/lib/posix_compat.sh"

set -e

# posix_reverse - Reverse lines in a file (replaces tac/tail -r)
# Usage: posix_reverse <file>
# Returns: Reversed lines on stdout
# Example: posix_reverse /tmp/stack.txt
posix_reverse() {
    _pr_file="$1"

    if [ ! -f "$_pr_file" ]; then
        printf 'ERROR: File not found: %s\n' "$_pr_file" >&2
        return 1
    fi

    # Use awk to reverse lines - pure POSIX
    awk '{lines[NR]=$0} END {for(i=NR;i>0;i--) print lines[i]}' "$_pr_file"

    unset _pr_file
    return 0
}

# posix_mktemp - Create temporary file safely (replaces mktemp)
# Usage: posix_mktemp [template]
# Returns: Path to created temp file on stdout
# Example: tmpfile=$(posix_mktemp)
posix_mktemp() {
    _pmt_template="${1:-tmp}"

    if command -v mktemp >/dev/null 2>&1; then
        # System has mktemp, use it
        mktemp "${TMPDIR:-/tmp}/${_pmt_template}.XXXXXXXX"
    else
        # Fallback for systems without mktemp
        _pmt_counter=0
        while [ $_pmt_counter -lt 100 ]; do
            _pmt_name="${TMPDIR:-/tmp}/${_pmt_template}.$$.$_pmt_counter"

            # Try to create exclusively (noclobber)
            (
                set -C
                : > "$_pmt_name"
            ) 2>/dev/null && {
                chmod 600 "$_pmt_name"
                printf '%s\n' "$_pmt_name"
                unset _pmt_template _pmt_counter _pmt_name
                return 0
            }

            _pmt_counter=$((_pmt_counter + 1))
        done

        printf 'ERROR: Failed to create temporary file after 100 attempts\n' >&2
        unset _pmt_template _pmt_counter _pmt_name
        return 1
    fi
}

# posix_sed_inplace - Atomically edit file in place (replaces sed -i)
# Usage: posix_sed_inplace <sed_expression> <file>
# Returns: 0 on success, 1 on failure
# Example: posix_sed_inplace 's/^Port .*/Port 2222/' /etc/ssh/sshd_config
posix_sed_inplace() {
    _psi_pattern="$1"
    _psi_file="$2"
    _psi_tmp=""
    _psi_result=0

    if [ -z "$_psi_pattern" ] || [ -z "$_psi_file" ]; then
        printf 'ERROR: Usage: posix_sed_inplace <pattern> <file>\n' >&2
        return 1
    fi

    if [ ! -f "$_psi_file" ]; then
        printf 'ERROR: File not found: %s\n' "$_psi_file" >&2
        return 1
    fi

    # Create temp file
    _psi_tmp=$(posix_mktemp "sed_inplace") || return 1

    # Apply sed to temp file
    if sed "$_psi_pattern" "$_psi_file" > "$_psi_tmp" 2>/dev/null; then
        # Preserve permissions and ownership
        if [ -r "$_psi_file" ]; then
            # Copy permissions
            chmod --reference="$_psi_file" "$_psi_tmp" 2>/dev/null ||
                chmod "$(stat -c '%a' "$_psi_file" 2>/dev/null || stat -f '%Mp%Lp' "$_psi_file")" "$_psi_tmp"

            # Atomic move
            mv "$_psi_tmp" "$_psi_file" || _psi_result=1
        else
            _psi_result=1
        fi
    else
        _psi_result=1
    fi

    # Cleanup
    [ -f "$_psi_tmp" ] && rm -f "$_psi_tmp"

    unset _psi_pattern _psi_file _psi_tmp
    return $_psi_result
}

# posix_realpath - Get absolute path (replaces realpath)
# Usage: posix_realpath <path>
# Returns: Absolute path on stdout
# Example: fullpath=$(posix_realpath ../file.txt)
posix_realpath() {
    _prp_path="$1"
    _prp_pwd_save="$PWD"
    _prp_result=""

    if [ -z "$_prp_path" ]; then
        printf 'ERROR: Usage: posix_realpath <path>\n' >&2
        return 1
    fi

    # If path is a directory
    if [ -d "$_prp_path" ]; then
        cd "$_prp_path" && _prp_result="$PWD"
        cd "$_prp_pwd_save"
    # If path is a file
    elif [ -f "$_prp_path" ]; then
        case "$_prp_path" in
            */*)
                _prp_dir="${_prp_path%/*}"
                _prp_file="${_prp_path##*/}"
                cd "$_prp_dir" && _prp_result="$PWD/$_prp_file"
                cd "$_prp_pwd_save"
                ;;
            *)
                _prp_result="$PWD/$_prp_path"
                ;;
        esac
    else
        printf 'ERROR: Path not found: %s\n' "$_prp_path" >&2
        unset _prp_path _prp_pwd_save _prp_result _prp_dir _prp_file
        return 1
    fi

    printf '%s\n' "$_prp_result"
    unset _prp_path _prp_pwd_save _prp_result _prp_dir _prp_file
    return 0
}

# posix_timeout - Run command with timeout (replaces timeout command)
# Usage: posix_timeout <seconds> <command> [args...]
# Returns: Command exit code, or 124 on timeout
# Example: posix_timeout 30 ssh user@host echo test
posix_timeout() {
    _pt_duration="$1"
    shift

    if [ -z "$_pt_duration" ]; then
        printf 'ERROR: Usage: posix_timeout <seconds> <command> [args...]\n' >&2
        return 1
    fi

    # Check for GNU timeout command
    if command -v timeout >/dev/null 2>&1; then
        timeout "$_pt_duration" "$@"
        return $?
    fi

    # Fallback implementation using shell backgrounding
    (
        "$@" &
        _pt_pid=$!
        _pt_count=0

        while [ $_pt_count -lt "$_pt_duration" ]; do
            if ! kill -0 $_pt_pid 2>/dev/null; then
                wait $_pt_pid
                exit $?
            fi
            sleep 1
            _pt_count=$((_pt_count + 1))
        done

        # Timeout reached
        kill -TERM $_pt_pid 2>/dev/null
        sleep 1
        kill -KILL $_pt_pid 2>/dev/null
        exit 124
    )
}

# posix_timestamp - Get current Unix timestamp (replaces date +%s)
# Usage: posix_timestamp
# Returns: Unix timestamp on stdout
# Example: now=$(posix_timestamp)
posix_timestamp() {
    # Try modern date command first
    if date +%s >/dev/null 2>&1; then
        date +%s
        return 0
    fi

    # Fallback using awk and date
    awk 'BEGIN {
        cmd = "date -u +\"%Y %m %d %H %M %S\""
        cmd | getline datestr
        close(cmd)

        split(datestr, d, " ")

        # Calculate days since epoch (1970-01-01)
        year = d[1]
        month = d[2]
        day = d[3]
        hour = d[4]
        min = d[5]
        sec = d[6]

        # Simple epoch calculation (not handling leap years perfectly)
        days = (year - 1970) * 365
        days += int((year - 1969) / 4)  # Leap years

        # Days in each month
        monthdays[1] = 31; monthdays[2] = 28; monthdays[3] = 31
        monthdays[4] = 30; monthdays[5] = 31; monthdays[6] = 30
        monthdays[7] = 31; monthdays[8] = 31; monthdays[9] = 30
        monthdays[10] = 31; monthdays[11] = 30; monthdays[12] = 31

        for (m = 1; m < month; m++) {
            days += monthdays[m]
        }
        days += day - 1

        timestamp = days * 86400 + hour * 3600 + min * 60 + sec
        print timestamp
    }'
}

# posix_join - Join array elements with delimiter (replaces ${arr[@]} bashism)
# Usage: posix_join <delimiter> <elements...>
# Returns: Joined string on stdout
# Example: result=$(posix_join "," "a" "b" "c")  # Returns: a,b,c
posix_join() {
    _pj_delim="$1"
    shift
    _pj_first=1

    for _pj_item in "$@"; do
        if [ $_pj_first -eq 1 ]; then
            printf '%s' "$_pj_item"
            _pj_first=0
        else
            printf '%s%s' "$_pj_delim" "$_pj_item"
        fi
    done

    unset _pj_delim _pj_first _pj_item
}

# Test if we're being sourced or executed
if [ "${0##*/}" = "posix_compat.sh" ]; then
    printf 'POSIX Compatibility Layer v1.0.0\n'
    printf 'This file should be sourced, not executed.\n'
    printf 'Usage: . /path/to/posix_compat.sh\n'
    exit 1
fi

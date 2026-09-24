#!/bin/sh
# Issue #19: every script registers undo actions for what it changes, so a
# script that fails after its changes leaves the system as it found it.
#
# For each script: take a snapshot, run it so it fails after all its changes
# (the completion marker is made unwritable), and compare. Then run it
# normally and check that it did change something, so the first comparison
# means something.
. "$(dirname "$0")/lib.sh"
cd "$TOOLKIT" || exit 1

STATE_DIR=/var/lib/hardening
LOG_DIR=/var/log/hardening
mkdir -p "$STATE_DIR" "$LOG_DIR"
# 01 and 02 only run inside an SSH session
SSH_CONNECTION="203.0.113.5 50000 172.17.0.2 22"; export SSH_CONNECTION

# A service for 11 to disable, enabled without a running systemd
cat > /etc/systemd/system/rbtest.service <<'UNIT'
[Unit]
Description=rollback test service
[Service]
ExecStart=/bin/sleep infinity
[Install]
WantedBy=multi-user.target
UNIT
systemctl enable rbtest >/dev/null 2>&1
DISABLE_SERVICES=rbtest; export DISABLE_SERVICES
# A host with cron (15), a separate /tmp that 12 remounts, and a loose
# /var/tmp for 12 to fix
touch /etc/crontab; chmod 644 /etc/crontab
mkdir -p /etc/cron.d /etc/cron.daily /etc/cron.hourly /etc/cron.monthly /etc/cron.weekly
mount -t tmpfs -o mode=1777 tmpfs /tmp
chmod 777 /var/tmp
# Something for 05 to fix, and an account for 09 to lock
touch /var/log/rbtest.log; chmod 666 /var/log/rbtest.log
touch /etc/rbtest-world; chmod 666 /etc/rbtest-world
mkdir -p /root/.ssh; chmod 755 /root/.ssh

SYSCTL_KEYS=$(sed -n 's/^\([a-z][a-z0-9_.-]*\) = .*/\1/p' \
    scripts/03-kernel-params.sh scripts/14-sysctl-hardening.sh | sort -u)

files_state() {
    for f in /etc/sysctl.conf /etc/security/limits.conf /etc/rsyslog.conf \
        /etc/audit/rules.d/hardening.rules /etc/login.defs \
        /etc/pam.d/common-password /etc/sudoers.d /etc/sudoers.d/hardening \
        /etc/cron.allow /etc/cron.deny /etc/at.allow /etc/at.deny \
        /etc/crontab /etc/cron.d /etc/cron.daily /etc/cron.hourly \
        /etc/cron.monthly /etc/cron.weekly /etc/profile \
        /etc/bash.bashrc /etc/issue /etc/issue.net /etc/motd \
        /etc/logrotate.conf /etc/logrotate.d/security /etc/ssh/sshd_config \
        /etc/ssh/banner /etc/ssh /etc/iptables /etc/iptables/rules.v4 \
        /etc/iptables/rules.v6 /etc/passwd /etc/shadow /etc/group \
        /tmp /var/tmp /var/log /var/log/rbtest.log /etc/rbtest-world \
        /root/.ssh /tmp/firewall_reset.sh \
        /etc/network/if-pre-up.d/iptables; do
        if [ -e "$f" ]; then
            printf '%s %s' "$f" "$(stat -c '%a %u %g' "$f")"
            [ -f "$f" ] && printf ' %s' "$(sha256sum < "$f" | cut -c1-16)"
            echo
        else
            echo "$f absent"
        fi
    done
    for f in "$STATE_DIR"/integrity_baseline*; do
        [ -e "$f" ] && echo "$f"
    done
}

kernel_state() {
    for k in $SYSCTL_KEYS fs.suid_dumpable; do
        printf '%s=%s\n' "$k" "$(sysctl -n "$k" 2>/dev/null || echo n/a)"
    done
    for p in /proc/sys/net/ipv4/conf/*/accept_source_route \
        /proc/sys/net/ipv4/conf/*/accept_redirects \
        /proc/sys/net/ipv4/conf/*/send_redirects \
        /proc/sys/net/ipv4/conf/*/rp_filter \
        /proc/sys/net/ipv6/conf/*/accept_ra; do
        [ -f "$p" ] && printf '%s=%s\n' "$p" "$(cat "$p")"
    done
    awk '$2 == "/proc" || $2 == "/dev/shm" || $2 == "/tmp" || $2 == "/home"' /proc/mounts
    iptables-save 2>/dev/null | rules
    ip6tables-save 2>/dev/null | rules
    echo "rbtest $(systemctl is-enabled rbtest 2>/dev/null)"
}

# iptables-save without counters, leaving out tables that only hold ACCEPT
# policies and no rules: loaded-but-open and never-loaded are the same
rules() {
    sed 's/\[[0-9:]*\]//' | awk '
        /^\*/ { t = $0; buf = ""; keep = 0; next }
        /^COMMIT/ { if (keep) print t buf; next }
        /^#/ { next }
        { buf = buf "\n" $0 }
        /^-A/ || (/^:/ && $2 != "ACCEPT") { keep = 1 }'
}

snapshot() { files_state; kernel_state; }

# 03 sets htcp, which this kernel lacks, so unchanged it fails on its own.
# That failure must also leave nothing behind.
before=$(snapshot)
sh scripts/03-kernel-params.sh </dev/null >/tmp/03-htcp.out 2>&1; rc=$?
check "03 with htcp: fails on this kernel" test "$rc" -ne 0
check "03 with htcp: rolled back" grep -q 'Rollback completed' /tmp/03-htcp.out
check_eq "03 with htcp: system unchanged" "$before" "$(snapshot)"

# From here 03 and 14 use cubic and skip the keys this container's network
# namespace does not have, so they can finish
sed -i 's/= htcp$/= cubic/' scripts/03-kernel-params.sh scripts/14-sysctl-hardening.sh
for k in $SYSCTL_KEYS; do
    sysctl -n "$k" >/dev/null 2>&1 && continue
    sed -i "/^$k = /d" scripts/03-kernel-params.sh scripts/14-sysctl-hardening.sh
done

run_script() {
    sh "scripts/$1.sh" </dev/null >"/tmp/$1.out" 2>&1
}

for s in 01-ssh-hardening 02-firewall-setup 03-kernel-params \
    04-network-stack 05-file-permissions 06-process-limits \
    07-audit-logging 08-password-policy 09-account-lockdown \
    10-sudo-restrictions 11-service-disable 12-tmp-hardening \
    13-core-dump-disable 14-sysctl-hardening 15-cron-restrictions \
    16-mount-options 17-shell-timeout 18-banner-warnings \
    19-log-retention 20-integrity-baseline; do
    before=$(snapshot)

    # Fail at mark_completed, after every change
    rm -rf "$STATE_DIR/completed"; mkdir -p "$STATE_DIR/completed"
    : > "$LOG_DIR/rollback.log"
    run_script "$s"; rc=$?
    after_fail=$(snapshot)
    rmdir "$STATE_DIR/completed"

    check "$s: fails when it cannot mark completion" test "$rc" -ne 0
    check "$s: rolled back" grep -q '|ROLLBACK|' "$LOG_DIR/rollback.log"
    if [ "$before" = "$after_fail" ]; then
        ok "$s: failed run leaves the system unchanged"
    else
        nok "$s: failed run leaves the system unchanged"
        diff "$(printf '%s\n' "$before" > /tmp/b; echo /tmp/b)" \
             "$(printf '%s\n' "$after_fail" > /tmp/a; echo /tmp/a)" | sed 's/^/#   /'
    fi

    # The same script, allowed to finish, does change this container
    run_script "$s"
    after_ok=$(snapshot)
    if [ "$before" != "$after_ok" ]; then
        ok "$s: a normal run changes something here"
    else
        nok "$s: a normal run changes something here"
        tail -5 "/tmp/$s.out" | sed 's/^/#   /'
    fi
done

# 00 reinstalls the SSH package, which this test cannot do offline. Check
# that it registers the restore of sshd_config and the reload, and that it
# loads the library that defines the reload.
check "00: restores sshd_config on rollback" \
    grep -q 'register_file_rollback /etc/ssh/sshd_config' scripts/00-ssh-verification.sh
check "00: reloads sshd on rollback" \
    grep -q 'register_command_rollback "ssh_reload_config"' scripts/00-ssh-verification.sh
check "00: loads ssh_reload_config" \
    grep -q 'LIB_DIR/ssh_safety.sh' scripts/00-ssh-verification.sh

check "12: deleting old temp files is declared irreversible" \
    grep -q 'rollback cannot undo' scripts/12-tmp-hardening.sh

finish

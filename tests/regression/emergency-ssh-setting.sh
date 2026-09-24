#!/bin/sh
# Issue #18: the emergency SSH setting must do what it says on the manual
# path, stay off unless it is asked for, and not print a false claim.
. "$(dirname "$0")/lib.sh"
cd "$TOOLKIT" || exit 1

listening_2222() { ss -ltn | grep -q ':2222 '; }
stop_emergency() {
    [ -f /var/run/sshd_emergency.pid ] && kill "$(cat /var/run/sshd_emergency.pid)" 2>/dev/null
    rm -f /var/run/sshd_emergency.pid; sleep 1
}
# 01-ssh-hardening.sh only considers emergency access inside an SSH session.
run_01() {
    SSH_CONNECTION="203.0.113.5 50000 172.17.0.2 22"; export SSH_CONNECTION
    sh scripts/01-ssh-hardening.sh >/tmp/01.out 2>&1
    unset SSH_CONNECTION
}
fresh_config() {
    cp config/defaults.conf.template config/defaults.conf
    sed -i 's/^SSH_ALLOW_USERS=.*/SSH_ALLOW_USERS="ansible"/' config/defaults.conf
}

# 1. Template default: off, and the output says so.
fresh_config
check "template ships ENABLE_EMERGENCY_SSH=0" grep -q '^ENABLE_EMERGENCY_SSH=0' config/defaults.conf
run_01
check "no emergency sshd with the default config" sh -c '! ss -ltn | grep -q ":2222 "'
check "output does not claim extra safety measures" \
    sh -c '! grep -q "extra safety measures enabled" /tmp/01.out'
check "output says emergency SSH is off" grep -q "emergency SSH is off" /tmp/01.out

# 2. The manual-path name turns it on.
fresh_config
sed -i 's/^ENABLE_EMERGENCY_SSH=.*/ENABLE_EMERGENCY_SSH=1/' config/defaults.conf
run_01
check "ENABLE_EMERGENCY_SSH=1 starts the emergency sshd on 2222" listening_2222
stop_emergency

# 3. The name the Ansible template writes still works.
fresh_config
sed -i '/^ENABLE_EMERGENCY_SSH=/d' config/defaults.conf
echo "ENABLE_EMERGENCY_ACCESS=1" >> config/defaults.conf
run_01
check "ENABLE_EMERGENCY_ACCESS=1 starts the emergency sshd" listening_2222
stop_emergency

# 4. Dry run never starts it.
fresh_config
sed -i 's/^ENABLE_EMERGENCY_SSH=.*/ENABLE_EMERGENCY_SSH=1/' config/defaults.conf
DRY_RUN=1; export DRY_RUN; run_01; unset DRY_RUN
check "DRY_RUN=1 does not start the emergency sshd" sh -c '! ss -ltn | grep -q ":2222 "'

# 5. quick-start.sh: the default answer leaves it off, "y" turns it on.
rm -f config/defaults.conf
printf '203.0.113.5\n\n\nansible\n\n\n\n\n\n\n\n\n\n\n\n\n' | sh quick-start.sh >/tmp/qs.out 2>&1
check_eq "quick-start default writes ENABLE_EMERGENCY_SSH=0" \
    "ENABLE_EMERGENCY_SSH=0" "$(grep -o '^ENABLE_EMERGENCY_SSH=[01]' config/defaults.conf)"
rm -f config/defaults.conf
printf '203.0.113.5\n\n\nansible\ny\n2222\n\n\n\n\n\n\n\n\n\n\n\n' | sh quick-start.sh >/tmp/qs.out 2>&1
check_eq "quick-start 'y' writes ENABLE_EMERGENCY_SSH=1" \
    "ENABLE_EMERGENCY_SSH=1" "$(grep -o '^ENABLE_EMERGENCY_SSH=[01]' config/defaults.conf)"

# 6. 00-ssh-verification.sh has a port even when the config omits it.
check "00-ssh-verification.sh defaults EMERGENCY_SSH_PORT to 2222" \
    grep -q 'EMERGENCY_SSH_PORT="${EMERGENCY_SSH_PORT:-2222}"' scripts/00-ssh-verification.sh

finish

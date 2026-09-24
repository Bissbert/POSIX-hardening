#!/bin/sh
# Issue #16: the repository must not ship SSH public keys that the playbooks
# deploy to every host, and generate_keys.sh must make the operator's own pair.
. "$(dirname "$0")/lib.sh"
cd "$TOOLKIT" || exit 1

KD=ansible/team_keys
PUB1=$KD/ansible_ed25519.pub
PUB2=$KD/team_shared_ed25519.pub
# A key known to be public: one of the pairs older versions shipped
OLD_FP='SHA256:S7Z7K/80/EdFifFBu7xnq8s5SAY3H2NGnweT4TguV9s'

# 1. Not in the committed tree. The image has no git, but the index stores
#    every tracked path as plain text.
check "ansible_ed25519.pub is not tracked" sh -c "! grep -aq '$PUB1' .git/index"
check "team_shared_ed25519.pub is not tracked" sh -c "! grep -aq '$PUB2' .git/index"
check ".gitignore does not re-admit team_keys/*.pub" \
    sh -c "! grep -q '^!ansible/team_keys/\*\.pub' .gitignore"
check ".gitignore ignores team_keys/*.pub" grep -qx 'ansible/team_keys/\*\.pub' .gitignore

clean_keys() { rm -f $KD/*.pub $KD/*_ed25519; }
gen() { echo n | sh $KD/generate_keys.sh >/tmp/gen.out 2>&1; }

# 2. A stray public key (as left by an older clone) must not stop generation.
clean_keys
printf 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGSsrb3JI2pMbyxjpu5xxPhrD4zTGe9XW5lr7uMlqeMe stray\n' > "$PUB1"
gen; rc=$?
check_eq "generate_keys exits 0 when both pairs are made" 0 "$rc"
check "ansible private key was generated despite the stray .pub" test -f $KD/ansible_ed25519
check "the stray .pub was replaced by the matching public key" \
    sh -c "ssh-keygen -y -f $KD/ansible_ed25519 | cut -d' ' -f2 | grep -qF \"\$(cut -d' ' -f2 $PUB1)\""
check "team private key was generated" test -f $KD/team_shared_ed25519
check "generated key is not a shipped one" sh -c "! ssh-keygen -lf $PUB1 | grep -qF '$OLD_FP'"

# 3. A missing public half is recreated from the private key.
rm -f "$PUB2"
gen
check "missing team .pub is recreated from the private key" \
    sh -c "ssh-keygen -y -f $KD/team_shared_ed25519 | cut -d' ' -f2 | grep -qF \"\$(cut -d' ' -f2 $PUB2)\""

# 4. If keys cannot be made, fail before offering to install anything.
clean_keys
mkdir -p /tmp/nokeygen
printf '#!/bin/sh\nexit 1\n' > /tmp/nokeygen/ssh-keygen
chmod +x /tmp/nokeygen/ssh-keygen
echo n | PATH="/tmp/nokeygen:$PATH" sh $KD/generate_keys.sh >/tmp/gen.out 2>&1; rc=$?
check "generate_keys exits non-zero when no key pair was made" test "$rc" -ne 0
check "it reports the incomplete pair" grep -q "is incomplete" /tmp/gen.out
check "it does not offer local installation" sh -c '! grep -q "Install team key on this machine" /tmp/gen.out'

finish

#!/bin/sh
# capture-ansible.sh - static facts about the two Ansible entry points.
#
# Read-only: nothing here contacts a managed host. Every ansible-playbook
# call is --syntax-check, which parses and exits. Run it through
# tools/host-tools-env.sh so it executes in a Linux container.
#
# Output: media/captures/ansible.txt
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
OUT="$ROOT/media/captures/ansible.txt"
mkdir -p "$ROOT/media/captures"

# Keep ansible-lint's cache out of the repository.
ANSIBLE_HOME=$(mktemp -d)
export ANSIBLE_HOME
trap 'rm -rf "$ANSIBLE_HOME"' EXIT INT TERM

cd "$ROOT/ansible"

{
    echo "=== 1. tool versions"
    ansible-playbook --version </dev/null 2>/dev/null | sed -n '1p' | sed 's/^/    /'
    ansible-lint --version </dev/null 2>/dev/null | sed 's/\[[0-9;]*m//g' | sed -n '1p' | sed 's/^/    /'

    echo
    echo "=== 2. which playbooks exist, and where"
    echo "    tracked playbooks at the ansible/ root and under ansible/playbooks/:"
    git -C "$ROOT" ls-files 'ansible/*.yml' 'ansible/playbooks/*.yml' \
        | grep -vE '^ansible/(roles|group_vars|host_vars|inventories|collections|testing|utils)/' \
        | sed 's/^/      /'

    echo
    echo "=== 3. duplicated playbooks: root copy vs playbooks/ copy"
    for f in site.yml preflight.yml rollback.yml deploy_team_keys.yml; do
        if diff -q "$f" "playbooks/$f" >/dev/null 2>&1; then
            printf '    %-22s identical\n' "$f"
        else
            printf '    %-22s differ: %s changed hunks\n' "$f" \
                "$(diff "$f" "playbooks/$f" | grep -c '^[0-9]')"
        fi
    done
    echo "    the substantive difference in preflight.yml:"
    diff preflight.yml playbooks/preflight.yml | sed -n '1,8p' | sed 's/^/      /'

    echo
    echo "=== 4. how each entry point applies the hardening"
    printf '    %-24s %s\n' "site.yml" \
        "$(grep -c 'posix_hardening_' site.yml) role references, $(grep -oE 'sh scripts/[0-9]+-[a-z-]+\.sh' site.yml | sort -u | wc -l | tr -d ' ') scripts named, $(grep -cE '^\s+- "[0-9]+-[a-z-]+\.sh"' site.yml) more in loops"
    printf '    %-24s %s\n' "hardening_master.yml" \
        "$(grep -cE '^\s+- role: posix_hardening_' hardening_master.yml) role references, $(grep -oE 'sh scripts/' hardening_master.yml | wc -l | tr -d ' ') script invocations"
    echo "    orchestrator.sh in site.yml:"
    grep -n 'orchestrator' site.yml | sed 's/^/      /'
    echo "    plays, and the priority levels each entry point defines:"
    printf '      %-24s %s plays, priorities: %s\n' "site.yml" \
        "$(grep -c '^- name:' site.yml)" \
        "$(grep -oE 'priority[0-9]' site.yml | sort -u | tr '\n' ' ')"
    printf '      %-24s %s plays, priorities: %s\n' "hardening_master.yml" \
        "$(grep -c '^- name:' hardening_master.yml)" \
        "$(grep -oE 'priority[0-9]' hardening_master.yml | sort -u | tr '\n' ' ')"
    printf '      %-24s priorities: %s\n' "../orchestrator.sh" \
        "$(grep -oE '^[0-9]+:[0-9]+-[a-z-]+\.sh:' ../orchestrator.sh | cut -d: -f1 | sort -u | tr '\n' ' ')"

    echo
    echo "=== 5. roles on disk vs roles a playbook uses"
    ls -1 roles | sort > /tmp/ph_disk.$$
    echo "    roles in ansible/roles/: $(wc -l < /tmp/ph_disk.$$ | tr -d ' ')"
    grep -hoE '^\s+- role: posix_hardening_[a-z]+' hardening_master.yml \
        | grep -oE 'posix_hardening_[a-z]+' | sort -u > /tmp/ph_master.$$
    echo "    roles used by hardening_master.yml: $(wc -l < /tmp/ph_master.$$ | tr -d ' ')"
    echo "    roles not reachable from hardening_master.yml, and what does use them:"
    comm -23 /tmp/ph_disk.$$ /tmp/ph_master.$$ | while read -r r; do
        _users=$(grep -lE "^\s+- role: $r\b" ./*.yml playbooks/*.yml 2>/dev/null \
            | tr '\n' ' ')
        printf '      %-26s %s\n' "$r" "${_users:-nothing}"
    done
    rm -f /tmp/ph_disk.$$ /tmp/ph_master.$$

    echo
    echo "=== 6. which inventory ansible.cfg actually loads"
    grep -E '^(inventory|remote_user|host_key_checking|roles_path) ' ansible.cfg \
        | sed 's/^/      /'
    echo "    file structure section of ansible/README.md names inventory.ini:"
    grep -n 'inventory.ini' README.md | head -2 | sed 's/^/      /'

    echo
    echo "=== 6b. do the relative src: paths in both copies of site.yml resolve"
    echo "    ansible resolves copy: src: against the playbook directory."
    for pb in site.yml playbooks/site.yml; do
        _dir=$(dirname "$pb")
        _shown=ansible/; [ "$_dir" = . ] || _shown="ansible/$_dir/"
        echo "    $pb:"
        grep -oE 'src: "[^"{]+"' "$pb" | sed 's/^src: "//; s/"$//' \
            | while read -r rel; do
                printf '      %-32s -> %-44s %s\n' "$rel" "$_shown$rel" \
                    "$(test -e "$_dir/$rel" && echo present || echo MISSING)"
            done
    done
    echo "    controlled reproduction of the resolution rule, so the"
    echo "    search path is visible rather than asserted:"
    _tmp=$(mktemp -d)
    mkdir -p "$_tmp/repo/lib" "$_tmp/repo/ansible/playbooks"
    echo x > "$_tmp/repo/lib/f.sh"
    cat > "$_tmp/repo/ansible/playbooks/p.yml" <<'PLAYBOOK'
- hosts: localhost
  connection: local
  gather_facts: false
  tasks:
    - ansible.builtin.copy:
        src: "../lib/"
        dest: "/tmp/ph-never-written/"
        mode: '0644'
PLAYBOOK
    ( cd "$_tmp/repo/ansible" \
      && ansible-playbook playbooks/p.yml -i localhost, </dev/null 2>&1 ) \
        | awk '{ gsub(/\\n\\t/, "\n"); print }' \
        | grep -oE '/ansible/playbooks[^ ]*/lib/' | sort -u \
        | sed 's|^|        |'
    rm -rf "$_tmp"
    echo "        (cwd is not among them: ../lib/ is ansible/playbooks/../lib/)"
    unset _tmp

    echo
    echo "=== 7. ansible-playbook --syntax-check"
    for p in site.yml hardening_master.yml preflight.yml rollback.yml \
             validate_config.yml deploy_team_keys.yml playbooks/site.yml \
             playbooks/preflight.yml playbooks/rollback.yml playbooks/validate.yml; do
        if ansible-playbook --syntax-check "$p" </dev/null >/dev/null 2>&1; then
            printf '    %-28s exit=0\n' "$p"
        else
            printf '    %-28s exit=%d\n' "$p" "$?"
        fi
    done

    echo
    echo "=== 8. ansible-lint over the six top-level playbooks"
    echo "    (this walks every role they pull in)"
    ansible-lint --nocolor -f pep8 \
        site.yml hardening_master.yml preflight.yml rollback.yml \
        validate_config.yml deploy_team_keys.yml \
        </dev/null >/tmp/ph_lint.$$ 2>/tmp/ph_lint_err.$$ || true
    sed -n '/Rule Violation Summary/,$p' /tmp/ph_lint_err.$$ \
        | grep -E '^\s*[0-9]+ |^Failed:' | sed 's/^/      /'
    rm -f /tmp/ph_lint.$$ /tmp/ph_lint_err.$$
} > "$OUT" 2>&1

echo "wrote $OUT"

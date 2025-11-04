# Ansible Quick Improvements Guide

**Quick-reference checklist for improving the POSIX-hardening Ansible deployment**

---

## Immediate Actions (1-2 Hours)

### 1. Update .gitignore

```bash
# Add to .gitignore
cat >> .gitignore << 'EOF'

# Ansible retry files
ansible/retry/
ansible/*.retry

# Ansible logs
ansible/ansible.log

# Inventory backups
ansible/inventory-generated.ini.backup.*
ansible/inventories/**/hosts.yml.backup.*

# Fact cache
/tmp/ansible_facts

# Vault password (never commit!)
.vault_pass
.vault_pass.txt
EOF
```

### 2. Add ansible-lint Configuration

```bash
# Create .ansible-lint file
cat > .ansible-lint << 'EOF'
---
profile: production

exclude_paths:
  - .cache/
  - .github/
  - ansible/retry/
  - ansible/testing/
  - testing/

skip_list:
  - yaml[line-length]
  - no-changed-when  # Fix gradually

warn_list:
  - experimental
  - role-name

offline: false
strict: false  # Set true when ready
EOF

# Install and run
pip install ansible-lint
ansible-lint ansible/*.yml
```

### 3. Add Collections Requirements

```bash
mkdir -p ansible/collections

cat > ansible/collections/requirements.yml << 'EOF'
---
collections:
  - name: ansible.posix
    version: ">=1.5.0"
  - name: community.general
    version: ">=6.0.0"
EOF

# Install collections
ansible-galaxy collection install -r ansible/collections/requirements.yml
```

### 4. Fix Shell Tasks with changed_when

Find all shell/command tasks and add `changed_when`:

```bash
cd ansible
grep -n "shell:\|command:" *.yml | grep -v "changed_when"
```

Add to each:
```yaml
changed_when: false  # If read-only operation
# OR
changed_when: result.rc == 0  # If actually makes changes
```

---

## Short-Term Improvements (1 Day)

### 5. Create Basic Role Structure

```bash
cd ansible
mkdir -p roles/{posix_hardening_deploy,posix_hardening_ssh,posix_hardening_firewall,posix_hardening_users}/{{tasks,handlers,templates,defaults},meta}

# Create main.yml files
for role in posix_hardening_deploy posix_hardening_ssh posix_hardening_firewall posix_hardening_users; do
    touch roles/$role/tasks/main.yml
    touch roles/$role/handlers/main.yml
    touch roles/$role/defaults/main.yml
    touch roles/$role/meta/main.yml
    touch roles/$role/README.md
done
```

### 6. Add Basic Handlers

Create `ansible/roles/posix_hardening_ssh/handlers/main.yml`:

```yaml
---
# SSH service handlers
- name: restart sshd
  ansible.builtin.systemd:
    name: sshd
    state: restarted
  listen: "restart sshd"

- name: reload sshd
  ansible.builtin.systemd:
    name: sshd
    state: reloaded
  listen: "reload sshd"

- name: test ssh connectivity
  ansible.builtin.wait_for_connection:
    timeout: 30
  listen: "test ssh connectivity"
```

### 7. Reorganize Inventory

```bash
cd ansible
mkdir -p inventories/{production,staging,testing}/{group_vars,host_vars}

# Move existing inventory
cp inventory.ini inventories/production/hosts.ini

# Create structure
cat > inventories/production/group_vars/all.yml << 'EOF'
---
# Production environment variables
environment: production
admin_ip: "CHANGE_ME"

# Override from parent group_vars/all.yml as needed
dry_run: false
run_full_hardening: true
EOF
```

Update `ansible.cfg`:
```ini
[defaults]
inventory = inventories/production/hosts.ini
```

### 8. Add Validation Role

Create `ansible/roles/posix_hardening_validation/tasks/validate_vars.yml`:

```yaml
---
# Critical variable validation
- name: Validate admin_ip is set
  ansible.builtin.assert:
    that:
      - admin_ip is defined
      - admin_ip != ""
      - admin_ip != "YOUR_ADMIN_IP_HERE"
      - admin_ip is match('^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}(/[0-9]{1,2})?$')
    fail_msg: "admin_ip must be set to a valid IP address or CIDR"
    success_msg: "admin_ip is valid: {{ admin_ip }}"

- name: Validate ssh_allow_users is not empty
  ansible.builtin.assert:
    that:
      - ssh_allow_users is defined
      - ssh_allow_users != ""
    fail_msg: "ssh_allow_users cannot be empty (root login will be disabled)"
    success_msg: "ssh_allow_users is set: {{ ssh_allow_users }}"

- name: Validate SSH port is in range
  ansible.builtin.assert:
    that:
      - ssh_port | int >= 1
      - ssh_port | int <= 65535
    fail_msg: "ssh_port must be between 1-65535"
    success_msg: "SSH port is valid: {{ ssh_port }}"
```

---

## Medium-Term Improvements (1 Week)

### 9. Convert SSH Hardening to Native Ansible

Create `ansible/roles/posix_hardening_ssh/tasks/main.yml`:

```yaml
---
- name: Include variable validation
  ansible.builtin.include_tasks: validate_vars.yml
  tags: [always]

- name: Backup SSH configuration
  ansible.builtin.copy:
    src: /etc/ssh/sshd_config
    dest: /etc/ssh/sshd_config.backup.{{ ansible_date_time.epoch }}
    remote_src: yes
    mode: '0600'
  tags: [ssh, backup]

- name: Configure SSH daemon
  ansible.builtin.lineinfile:
    path: /etc/ssh/sshd_config
    regexp: "{{ item.regexp }}"
    line: "{{ item.line }}"
    state: present
    validate: '/usr/sbin/sshd -t -f %s'
    backup: yes
  loop:
    - { regexp: '^#?PermitRootLogin', line: 'PermitRootLogin no' }
    - { regexp: '^#?PasswordAuthentication', line: 'PasswordAuthentication no' }
    - { regexp: '^#?PubkeyAuthentication', line: 'PubkeyAuthentication yes' }
    - { regexp: '^#?Port', line: 'Port {{ ssh_port }}' }
    - { regexp: '^#?AllowUsers', line: 'AllowUsers {{ ssh_allow_users }}' }
    - { regexp: '^#?MaxAuthTries', line: 'MaxAuthTries 3' }
    - { regexp: '^#?ClientAliveInterval', line: 'ClientAliveInterval 300' }
    - { regexp: '^#?ClientAliveCountMax', line: 'ClientAliveCountMax 2' }
    - { regexp: '^#?X11Forwarding', line: 'X11Forwarding no' }
    - { regexp: '^#?PermitEmptyPasswords', line: 'PermitEmptyPasswords no' }
  notify:
    - restart sshd
    - test ssh connectivity
  tags: [ssh, hardening]

- name: Ensure SSH service is enabled
  ansible.builtin.systemd:
    name: sshd
    enabled: yes
  tags: [ssh]
```

### 10. Convert Firewall to Native Ansible

Create `ansible/roles/posix_hardening_firewall/tasks/main.yml`:

```yaml
---
- name: Install iptables-persistent
  ansible.builtin.apt:
    name: iptables-persistent
    state: present
    update_cache: yes
  tags: [firewall, packages]

- name: Allow SSH port
  ansible.builtin.iptables:
    chain: INPUT
    protocol: tcp
    destination_port: "{{ ssh_port }}"
    source: "{{ admin_ip }}"
    jump: ACCEPT
    comment: "Allow SSH from admin IP"
  notify: save iptables rules
  tags: [firewall]

- name: Allow additional ports
  ansible.builtin.iptables:
    chain: INPUT
    protocol: tcp
    destination_port: "{{ item }}"
    jump: ACCEPT
    comment: "Allow port {{ item }}"
  loop: "{{ allowed_ports }}"
  when: allowed_ports is defined and allowed_ports | length > 0
  notify: save iptables rules
  tags: [firewall]

- name: Set default policies
  ansible.builtin.iptables:
    chain: "{{ item.chain }}"
    policy: "{{ item.policy }}"
  loop:
    - { chain: INPUT, policy: DROP }
    - { chain: FORWARD, policy: DROP }
    - { chain: OUTPUT, policy: ACCEPT }
  notify: save iptables rules
  tags: [firewall]
```

Add handler in `ansible/roles/posix_hardening_firewall/handlers/main.yml`:

```yaml
---
- name: save iptables rules
  ansible.builtin.shell: |
    iptables-save > /etc/iptables/rules.v4
    ip6tables-save > /etc/iptables/rules.v6
  listen: "save iptables rules"
```

### 11. Convert Sysctl to Native Ansible

Create `ansible/roles/posix_hardening_kernel/tasks/main.yml`:

```yaml
---
- name: Apply kernel hardening parameters
  ansible.posix.sysctl:
    name: "{{ item.key }}"
    value: "{{ item.value }}"
    state: present
    sysctl_file: /etc/sysctl.d/99-hardening.conf
    reload: yes
  loop: "{{ posix_kernel_parameters | dict2items }}"
  tags: [kernel, sysctl]
```

Add defaults in `ansible/roles/posix_hardening_kernel/defaults/main.yml`:

```yaml
---
posix_kernel_parameters:
  # Network security
  net.ipv4.conf.all.accept_source_route: 0
  net.ipv4.conf.default.accept_source_route: 0
  net.ipv4.conf.all.accept_redirects: 0
  net.ipv4.conf.default.accept_redirects: 0
  net.ipv4.conf.all.send_redirects: 0
  net.ipv4.conf.default.send_redirects: 0
  net.ipv4.conf.all.secure_redirects: 0
  net.ipv4.conf.default.secure_redirects: 0
  net.ipv4.tcp_syncookies: 1
  net.ipv4.icmp_echo_ignore_broadcasts: 1
  net.ipv4.icmp_ignore_bogus_error_responses: 1

  # IPv6 (disable if not used)
  net.ipv6.conf.all.disable_ipv6: 1
  net.ipv6.conf.default.disable_ipv6: 1

  # Kernel hardening
  kernel.dmesg_restrict: 1
  kernel.kptr_restrict: 2
  kernel.yama.ptrace_scope: 1
  fs.suid_dumpable: 0
```

### 12. Create Simplified site.yml

Create `ansible/playbooks/site.yml`:

```yaml
---
# ==============================================================================
# POSIX Hardening Deployment Playbook
# ==============================================================================

- name: Pre-flight Validation
  hosts: all
  gather_facts: yes
  tags: [always, preflight]

  roles:
    - role: posix_hardening_validation
      tags: [validation]

- name: Deploy POSIX Hardening Toolkit
  hosts: all
  become: yes
  tags: [deploy]

  roles:
    - role: posix_hardening_deploy
      tags: [deploy]

- name: Configure Users and SSH Keys
  hosts: all
  become: yes
  tags: [users, priority1]

  roles:
    - role: posix_hardening_users
      tags: [users]

- name: Harden SSH Configuration
  hosts: all
  become: yes
  tags: [ssh, priority1]

  roles:
    - role: posix_hardening_ssh
      tags: [ssh]

- name: Configure Firewall
  hosts: all
  become: yes
  tags: [firewall, priority1]

  roles:
    - role: posix_hardening_firewall
      tags: [firewall]

- name: Harden Kernel Parameters
  hosts: all
  become: yes
  tags: [kernel, priority2]

  roles:
    - role: posix_hardening_kernel
      tags: [kernel]

- name: Final Validation
  hosts: all
  become: yes
  tags: [validate]

  roles:
    - role: posix_hardening_validation
      vars:
        posix_validation_mode: full
      tags: [validation]
```

---

## Long-Term Improvements (2-4 Weeks)

### 13. Implement Ansible Vault

```bash
# Create vault password file (DO NOT COMMIT)
echo "your-secure-password" > ~/.ansible/vault_pass.txt
chmod 600 ~/.ansible/vault_pass.txt

# Update ansible.cfg
cat >> ansible/ansible.cfg << 'EOF'

# Vault password file
vault_password_file = ~/.ansible/vault_pass.txt
EOF

# Create encrypted vars
cd ansible
ansible-vault create inventories/production/group_vars/vault.yml
```

Add to vault.yml:
```yaml
---
vault_admin_ip: "203.0.113.10"
vault_api_keys:
  monitoring: "secret-key"
```

Reference in plaintext vars:
```yaml
# inventories/production/group_vars/all.yml
admin_ip: "{{ vault_admin_ip }}"
```

### 14. Add Molecule Testing

```bash
# Install molecule
pip install molecule molecule-docker ansible-lint

# Initialize in a role
cd ansible/roles/posix_hardening_ssh
molecule init scenario

# Customize molecule.yml
cat > molecule/default/molecule.yml << 'EOF'
---
driver:
  name: docker

platforms:
  - name: debian-11
    image: debian:11
    pre_build_image: true
    command: /sbin/init
    privileged: true
    volumes:
      - /sys/fs/cgroup:/sys/fs/cgroup:ro

provisioner:
  name: ansible
  config_options:
    defaults:
      callbacks_enabled: profile_tasks

verifier:
  name: ansible
EOF

# Run tests
molecule test
```

### 15. Add CI/CD Pipeline

Create `.github/workflows/ansible-ci.yml`:

```yaml
---
name: Ansible CI

on:
  push:
    branches: [main]
    paths:
      - 'ansible/**'
  pull_request:
    branches: [main]
    paths:
      - 'ansible/**'

jobs:
  lint:
    name: Lint Ansible
    runs-on: ubuntu-latest

    steps:
      - name: Checkout code
        uses: actions/checkout@v3

      - name: Set up Python
        uses: actions/setup-python@v4
        with:
          python-version: '3.10'

      - name: Install dependencies
        run: |
          pip install ansible ansible-lint yamllint

      - name: Run ansible-lint
        run: |
          cd ansible
          ansible-lint playbooks/*.yml roles/

      - name: Run yamllint
        run: |
          yamllint -c .yamllint ansible/

      - name: Syntax check
        run: |
          cd ansible
          ansible-playbook --syntax-check playbooks/site.yml

  test:
    name: Test with Docker
    runs-on: ubuntu-latest
    needs: lint

    steps:
      - name: Checkout code
        uses: actions/checkout@v3

      - name: Set up Python
        uses: actions/setup-python@v4
        with:
          python-version: '3.10'

      - name: Install Ansible
        run: pip install ansible

      - name: Run Docker tests
        run: |
          cd ansible/testing
          ./test-runner.sh full
```

---

## Checklist for Complete Migration

### Foundation
- [ ] Update .gitignore
- [ ] Add ansible-lint config
- [ ] Create collections/requirements.yml
- [ ] Install collections
- [ ] Fix shell tasks with changed_when

### Structure
- [ ] Create role directories
- [ ] Reorganize inventory into inventories/
- [ ] Move templates into roles
- [ ] Create playbooks/ directory
- [ ] Update ansible.cfg paths

### Roles
- [ ] Create posix_hardening_validation role
- [ ] Create posix_hardening_deploy role
- [ ] Create posix_hardening_users role
- [ ] Create posix_hardening_ssh role
- [ ] Create posix_hardening_firewall role
- [ ] Create posix_hardening_kernel role

### Handlers
- [ ] Add handlers to each role
- [ ] Update tasks to use notify
- [ ] Test handler execution

### Variables
- [ ] Standardize boolean formats
- [ ] Convert string lists to arrays
- [ ] Add defaults to all roles
- [ ] Implement Ansible Vault
- [ ] Add variable validation

### Testing
- [ ] Set up molecule for each role
- [ ] Add CI/CD pipeline
- [ ] Create validation assertions
- [ ] Test in Docker environment
- [ ] Test on real systems

### Documentation
- [ ] Write README for each role
- [ ] Document variable precedence
- [ ] Update main README
- [ ] Create migration guide
- [ ] Document testing procedures

---

## Testing After Changes

```bash
# 1. Syntax check
cd ansible
ansible-playbook --syntax-check playbooks/site.yml

# 2. Lint check
ansible-lint playbooks/*.yml roles/

# 3. Check mode (dry run)
ansible-playbook -i inventories/testing playbooks/site.yml --check

# 4. Docker test
cd testing
./test-runner.sh full

# 5. Production deployment (after all tests pass)
ansible-playbook -i inventories/production playbooks/site.yml --limit staging
```

---

## Common Issues and Solutions

### Issue: "role not found"
**Solution:** Update ansible.cfg to include roles path:
```ini
[defaults]
roles_path = ./roles:~/.ansible/roles:/etc/ansible/roles
```

### Issue: "template not found"
**Solution:** Ensure template is in role's templates/ directory and referenced without path:
```yaml
template:
  src: sshd_config.j2  # NOT templates/sshd_config.j2
```

### Issue: "handler not notified"
**Solution:** Ensure handler name matches exactly:
```yaml
# Task
notify: restart sshd

# Handler (exact match required)
- name: restart sshd
```

### Issue: "variable undefined"
**Solution:** Add defaults in role's defaults/main.yml:
```yaml
# roles/posix_hardening_ssh/defaults/main.yml
posix_ssh_port: 22
```

---

## Quick Command Reference

```bash
# Syntax check
ansible-playbook --syntax-check playbooks/site.yml

# Check mode (test without changes)
ansible-playbook playbooks/site.yml --check

# Diff mode (show changes)
ansible-playbook playbooks/site.yml --check --diff

# Run specific tags
ansible-playbook playbooks/site.yml --tags ssh,firewall

# Skip tags
ansible-playbook playbooks/site.yml --skip-tags priority3,priority4

# Limit to hosts
ansible-playbook playbooks/site.yml --limit production

# Verbose output
ansible-playbook playbooks/site.yml -vvv

# List tasks
ansible-playbook playbooks/site.yml --list-tasks

# List tags
ansible-playbook playbooks/site.yml --list-tags

# Ansible-lint
ansible-lint playbooks/*.yml

# Molecule test
cd roles/posix_hardening_ssh
molecule test

# Inventory graph
ansible-inventory --graph
```

---

## Priority Order

**Week 1:**
1. .gitignore updates
2. ansible-lint setup
3. Collections requirements
4. Fix changed_when

**Week 2:**
5. Create role structure
6. Add basic handlers
7. Reorganize inventory
8. Add validation role

**Week 3:**
9. Convert SSH to native Ansible
10. Convert firewall to native
11. Convert sysctl to native
12. Simplify site.yml

**Week 4:**
13. Implement Vault
14. Add molecule testing
15. Add CI/CD pipeline

This guide provides concrete, copy-paste commands for implementing the recommendations from the main review document.

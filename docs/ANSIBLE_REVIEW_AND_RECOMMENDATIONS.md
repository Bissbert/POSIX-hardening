# Ansible Structure Review and Recommendations

**Project:** POSIX Hardening Toolkit
**Review Date:** 2025-11-04

---

## Executive Summary

The POSIX-hardening project demonstrates **strong fundamentals** with good safety practices and comprehensive documentation. However, the current structure deviates significantly from Ansible best practices and would benefit from refactoring to a **role-based architecture** with proper separation of concerns.

**Overall Grade: B+ (Good, with significant room for improvement)**

### Key Strengths
- Excellent safety mechanisms (emergency SSH, rollback procedures)
- Comprehensive variable documentation in `group_vars/all.yml`
- Well-structured pre-flight checks and validation
- Good use of tags for incremental deployment
- Extensive inline documentation

### Critical Issues
- No roles directory structure (canonical Ansible pattern missing)
- All logic embedded in monolithic playbooks (558 lines in `site.yml`)
- Shell script execution instead of native Ansible modules
- No handler definitions (restarts are inline)
- Missing idempotence checks for many tasks
- No Ansible Vault usage for secrets
- Retry files tracked in git (should be ignored)

---

## Detailed Assessment

### 1. Playbook Structure and Organization

#### Current State

**Files:**
```
ansible/
├── site.yml (558 lines) - Main deployment
├── preflight.yml (282 lines) - Pre-flight checks
├── validate_config.yml (290 lines) - Configuration validation
├── rollback.yml (233 lines) - Emergency rollback
└── deploy_team_keys.yml (256 lines) - SSH key deployment
```

**Issues:**

1. **Monolithic Playbooks**: `site.yml` contains 558 lines with 5 plays and inline task definitions
   - Mixes concerns: deployment, user creation, key deployment, hardening execution
   - Hard to test individual components
   - Difficult to maintain and extend

2. **Shell-Heavy Approach**: Most hardening tasks use `shell:` module
   ```yaml
   - name: Execute SSH hardening
     shell: |
       cd {{ toolkit_path }}
       sh scripts/01-ssh-hardening.sh
   ```
   - **Anti-pattern**: Shell scripts are opaque to Ansible
   - No idempotence guarantees
   - Cannot leverage Ansible's change detection
   - Difficult to test with `--check` mode

3. **No Task Organization**: All tasks are inline in plays
   - No reusable task files
   - No includes or imports
   - Lots of duplication

**Recommendations:**

**HIGH PRIORITY:**

1. **Create Role-Based Structure**
   ```
   ansible/
   ├── playbooks/
   │   ├── site.yml
   │   ├── preflight.yml
   │   ├── rollback.yml
   │   └── validate.yml
   ├── roles/
   │   ├── posix_hardening_deploy/
   │   │   ├── tasks/main.yml
   │   │   ├── handlers/main.yml
   │   │   ├── templates/
   │   │   └── defaults/main.yml
   │   ├── posix_hardening_ssh/
   │   │   ├── tasks/main.yml
   │   │   ├── handlers/main.yml
   │   │   └── templates/sshd_config.j2
   │   ├── posix_hardening_firewall/
   │   ├── posix_hardening_users/
   │   └── posix_hardening_validation/
   └── collections/
       └── requirements.yml
   ```

2. **Convert Shell Scripts to Native Ansible Tasks**

   Instead of:
   ```yaml
   - name: Execute SSH hardening
     shell: cd /opt/posix-hardening && sh scripts/01-ssh-hardening.sh
   ```

   Use:
   ```yaml
   - name: Configure SSH daemon
     ansible.builtin.lineinfile:
       path: /etc/ssh/sshd_config
       regexp: "{{ item.regexp }}"
       line: "{{ item.line }}"
       validate: '/usr/sbin/sshd -t -f %s'
     loop:
       - { regexp: '^PermitRootLogin', line: 'PermitRootLogin no' }
       - { regexp: '^PasswordAuthentication', line: 'PasswordAuthentication no' }
     notify: restart sshd
   ```

3. **Split Monolithic Playbooks**
   - One concern per play
   - Use `import_playbook` or `include_playbook` for composition
   - Keep individual playbooks under 100 lines

**MEDIUM PRIORITY:**

4. **Create Task Files for Reusable Logic**
   ```yaml
   # roles/common/tasks/backup_config.yml
   - name: Backup configuration file
     ansible.builtin.copy:
       src: "{{ config_file }}"
       dest: "{{ config_file }}.backup.{{ ansible_date_time.epoch }}"
       remote_src: yes
   ```

5. **Use Block/Rescue/Always for Error Handling**
   ```yaml
   - name: SSH hardening with rollback
     block:
       - name: Backup SSH config
         ansible.builtin.copy:
           src: /etc/ssh/sshd_config
           dest: /etc/ssh/sshd_config.backup
           remote_src: yes

       - name: Apply SSH hardening
         ansible.builtin.template:
           src: sshd_config.j2
           dest: /etc/ssh/sshd_config
           validate: '/usr/sbin/sshd -t -f %s'
         notify: restart sshd

     rescue:
       - name: Restore backup on failure
         ansible.builtin.copy:
           src: /etc/ssh/sshd_config.backup
           dest: /etc/ssh/sshd_config
           remote_src: yes
         notify: restart sshd

       - name: Fail with message
         ansible.builtin.fail:
           msg: "SSH hardening failed, config restored"
   ```

---

### 2. Role Definitions and Organization

#### Current State

**No roles exist.** All logic is in playbooks.

**Impact:**
- Cannot leverage `ansible-galaxy` for distribution
- No dependency management
- Cannot version individual components
- Hard to reuse across projects

**Recommendations:**

**HIGH PRIORITY:**

1. **Create Core Roles**

   **Role: posix_hardening_deploy**
   - Purpose: Deploy toolkit files to targets
   - Tasks: Create directories, copy scripts/libraries, deploy templates
   - Handlers: None required

   **Role: posix_hardening_users**
   - Purpose: Create allowed users, deploy SSH keys
   - Tasks: User creation, .ssh directory setup, authorized_keys deployment
   - Handlers: None required

   **Role: posix_hardening_ssh**
   - Purpose: Harden SSH configuration
   - Tasks: Modify sshd_config, create emergency access, test connectivity
   - Handlers: `restart sshd`, `test ssh connectivity`
   - Templates: `sshd_config.j2`

   **Role: posix_hardening_firewall**
   - Purpose: Configure iptables rules
   - Tasks: Install iptables, configure rules, test connectivity
   - Handlers: `restart iptables-persistent`
   - Templates: `iptables.rules.j2`

   **Role: posix_hardening_kernel**
   - Purpose: Apply kernel hardening (sysctl)
   - Tasks: Set kernel parameters
   - Handlers: `reload sysctl`
   - Templates: `99-hardening.conf.j2`

   **Role: posix_hardening_validation**
   - Purpose: Validate hardening state
   - Tasks: Run checks, generate reports
   - Handlers: None required

2. **Create Role Defaults**

   Each role should have `defaults/main.yml`:
   ```yaml
   ---
   # roles/posix_hardening_ssh/defaults/main.yml
   posix_ssh_port: 22
   posix_ssh_permit_root_login: "no"
   posix_ssh_password_authentication: "no"
   posix_ssh_pubkey_authentication: "yes"
   posix_ssh_max_auth_tries: 3
   posix_ssh_client_alive_interval: 300
   posix_ssh_client_alive_count_max: 2
   ```

3. **Add Role Meta Information**
   ```yaml
   ---
   # roles/posix_hardening_ssh/meta/main.yml
   galaxy_info:
     author: POSIX Hardening Team
     description: SSH hardening for Debian-based systems
     license: MIT
     min_ansible_version: "2.10"
     platforms:
       - name: Debian
         versions:
           - bullseye
           - bookworm
       - name: Ubuntu
         versions:
           - focal
           - jammy

   dependencies:
     - role: posix_hardening_users
   ```

4. **Role Dependencies**
   Define clear dependencies in `meta/main.yml` to ensure proper execution order.

**MEDIUM PRIORITY:**

5. **Create Role README Files**
   Each role should have documentation:
   - Purpose and scope
   - Variables (required and optional)
   - Example playbook usage
   - Dependencies
   - Limitations

---

### 3. Inventory Management

#### Current State

**Files:**
```
ansible/
├── inventory.ini (static, mostly empty template)
├── inventory-generated.ini (dynamic, from nmap)
├── inventory-docker.ini (testing)
├── utils/generate-inventory.sh (network discovery)
└── utils/inventory-config.yml (scanner config)
```

**Good Practices:**
- Automated inventory generation with network scanning
- Separate testing inventory for Docker
- Environment-based groups (production, staging, test)
- Auto-detection of SSH ports and services

**Issues:**

1. **Multiple Inventory Files Without Clear Convention**
   - `inventory.ini` (template)
   - `inventory-generated.ini` (generated)
   - `inventory-docker.ini` (testing)
   - No clear "source of truth"

2. **Generated Inventory Backups Tracked in Git**
   ```
   inventory-generated.ini.backup.20251021-101009
   inventory-generated.ini.backup.20251021-101015
   ```
   These should be in `.gitignore`

3. **Static Inventory File is Mostly Placeholder**
   ```ini
   [production]
   # server1.example.com ansible_host=192.168.1.10 ...
   ```
   All commented out

4. **No Inventory Directory Structure**
   Current: All .ini files in root `ansible/` directory
   Best practice: `inventories/ENV/` structure

5. **admin_ip Set in Multiple Places**
   - `inventory.ini` (per-environment vars)
   - `group_vars/all.yml` (default empty)
   - Auto-detected by scanner

   Unclear precedence and potential conflicts

**Recommendations:**

**HIGH PRIORITY:**

1. **Adopt Standard Inventory Directory Structure**
   ```
   ansible/
   ├── inventories/
   │   ├── production/
   │   │   ├── hosts.yml (or hosts.ini)
   │   │   ├── group_vars/
   │   │   │   ├── all.yml
   │   │   │   └── production.yml
   │   │   └── host_vars/
   │   ├── staging/
   │   │   ├── hosts.yml
   │   │   └── group_vars/
   │   │       ├── all.yml
   │   │       └── staging.yml
   │   ├── testing/
   │   │   └── hosts.yml
   │   └── docker/
   │       └── hosts.yml
   └── group_vars/
       └── all.yml (shared defaults)
   ```

2. **Update ansible.cfg to Support Multi-Inventory**
   ```ini
   [defaults]
   # Default to production, override with -i flag
   inventory = inventories/production/hosts.yml

   # Or keep flexible
   # inventory = inventories/
   ```

3. **Create .gitignore Rules for Generated Files**
   ```gitignore
   # Inventory backups
   ansible/inventory-generated.ini.backup.*
   ansible/inventories/*/hosts.yml.backup.*

   # Generated inventories (source is utils/inventory-config.yml)
   ansible/inventory-generated.ini

   # Retry files
   ansible/retry/
   *.retry

   # Ansible logs
   ansible/ansible.log

   # Fact cache
   /tmp/ansible_facts
   ```

4. **Standardize on YAML Inventory Format**

   Current `.ini` format is valid but YAML offers better structure:
   ```yaml
   ---
   # inventories/production/hosts.yml
   all:
     children:
       production:
         hosts:
           server1:
             ansible_host: 192.168.1.10
             ansible_port: 22
             ansible_user: admin
         vars:
           admin_ip: "203.0.113.10"
           environment: production
   ```

**MEDIUM PRIORITY:**

5. **Document Inventory Management Workflow**
   Create `docs/INVENTORY_MANAGEMENT.md`:
   - When to use static vs generated inventory
   - How to run inventory generator
   - How to add new hosts manually
   - Variable precedence and override patterns

6. **Add Inventory Validation Script**
   ```bash
   #!/bin/bash
   # utils/validate-inventory.sh
   ansible-inventory -i inventories/production --list --yaml
   ansible-inventory -i inventories/production --graph
   ```

7. **Consider Dynamic Inventory Plugin**

   Instead of shell script + nmap, create proper Ansible dynamic inventory plugin:
   ```python
   # plugins/inventory/posix_nmap.py
   class InventoryModule(BaseInventoryPlugin):
       NAME = 'posix_nmap'

       def parse(self, inventory, loader, path, cache=True):
           # Read config from inventory-config.yml
           # Run nmap scans
           # Populate inventory
   ```

---

### 4. Variable Management

#### Current State

**Files:**
```
ansible/
├── group_vars/
│   └── all.yml (180 lines, comprehensive)
├── host_vars/ (empty directory)
└── inventory.ini (vars in [group:vars] sections)
```

**Good Practices:**
- Excellent documentation in `group_vars/all.yml`
- Clear variable categorization (safety, SSH, firewall, etc.)
- Inline comments explaining each variable
- Sensible defaults for most settings

**Issues:**

1. **Variable Precedence Confusion**

   `admin_ip` is defined in THREE places:
   - `group_vars/all.yml`: `admin_ip: ""` (empty default)
   - `inventory.ini [production:vars]`: `admin_ip=YOUR_ADMIN_IP_HERE`
   - Generated by scanner: auto-detected from network

   This creates confusion about where to set the value.

2. **No Ansible Vault Usage**

   Currently no secrets are vaulted. While SSH keys are properly excluded from git, there's no mechanism for encrypting sensitive vars like:
   - API keys (if added later)
   - Sudo passwords (if needed)
   - Service credentials

3. **Boolean Inconsistency**

   Mix of formats:
   - `enable_firewall: true` (YAML boolean)
   - `safety_mode: 1` (integer flag)
   - `dry_run: 0` (integer flag)

   Should standardize on one format.

4. **No Environment-Specific Variable Files**

   All environments share `group_vars/all.yml`. No production-specific or staging-specific variable files beyond inventory inline vars.

5. **Template Variables Lack Defaults**

   In `defaults.conf.j2`:
   ```jinja
   SSH_ALLOW_USERS="{{ ssh_allow_users }}"
   ```
   If `ssh_allow_users` is undefined, template will fail. Should use:
   ```jinja
   SSH_ALLOW_USERS="{{ ssh_allow_users | default('') }}"
   ```

6. **Lists Stored as Space-Separated Strings**
   ```yaml
   ssh_allow_users: "admin"  # Should be a list
   ssh_allow_groups: ""      # Should be a list
   ```

   Shell scripts parse these, but it's not idiomatic Ansible.

**Recommendations:**

**HIGH PRIORITY:**

1. **Adopt Environment-Specific Group Vars**
   ```
   ansible/
   ├── group_vars/
   │   ├── all.yml (shared defaults across ALL environments)
   │   ├── production.yml (production-only vars)
   │   ├── staging.yml (staging-only vars)
   │   └── test.yml (test-only vars)
   └── inventories/
       ├── production/
       │   └── group_vars/
       │       ├── all.yml (production environment-specific)
       │       └── vault.yml (encrypted secrets)
       └── staging/
           └── group_vars/
               ├── all.yml
               └── vault.yml
   ```

2. **Implement Ansible Vault for Secrets**
   ```bash
   # Create vault password file (DO NOT commit to git)
   echo "your-vault-password" > ~/.ansible/vault_pass.txt
   chmod 600 ~/.ansible/vault_pass.txt

   # Create encrypted vars file
   ansible-vault create inventories/production/group_vars/vault.yml

   # Add to ansible.cfg
   # vault_password_file = ~/.ansible/vault_pass.txt
   ```

   Example vault file:
   ```yaml
   ---
   # inventories/production/group_vars/vault.yml
   vault_admin_ip: "203.0.113.10"
   vault_sudo_password: "secure_password_here"
   vault_api_keys:
     monitoring: "abc123..."
   ```

   Reference in plaintext vars:
   ```yaml
   # inventories/production/group_vars/all.yml
   admin_ip: "{{ vault_admin_ip }}"
   sudo_password: "{{ vault_sudo_password }}"
   ```

3. **Standardize Boolean Representations**

   Choose one format and stick to it. Recommendation: **YAML booleans**
   ```yaml
   # Good (YAML boolean)
   enable_firewall: true
   safety_mode: true
   dry_run: false

   # Update templates accordingly
   ENABLE_FIREWALL={{ enable_firewall | bool | int }}
   ```

4. **Convert String Lists to Actual Lists**
   ```yaml
   # Before
   ssh_allow_users: "admin deploy"

   # After
   ssh_allow_users:
     - admin
     - deploy

   # In templates
   SSH_ALLOW_USERS="{{ ssh_allow_users | join(' ') }}"

   # In tasks
   - name: Create SSH allowed users
     ansible.builtin.user:
       name: "{{ item }}"
     loop: "{{ ssh_allow_users }}"
   ```

5. **Add Defaults to All Template Variables**
   ```jinja
   # templates/defaults.conf.j2
   SSH_ALLOW_USERS="{{ ssh_allow_users | default([]) | join(' ') }}"
   ALLOWED_PORTS="{{ allowed_ports | default([]) | join(' ') }}"
   TRUSTED_NETWORKS="{{ trusted_networks | default([]) | join(' ') }}"
   ```

**MEDIUM PRIORITY:**

6. **Document Variable Precedence**

   Create `docs/VARIABLE_PRECEDENCE.md`:
   ```markdown
   # Variable Precedence in POSIX Hardening

   From highest to lowest priority:
   1. Extra vars (`-e` on command line)
   2. Task vars
   3. Block vars
   4. Role vars
   5. Play vars
   6. inventories/ENV/host_vars/HOST.yml
   7. inventories/ENV/group_vars/GROUP.yml
   8. group_vars/GROUP.yml
   9. inventories/ENV/group_vars/all.yml
   10. group_vars/all.yml
   11. roles/ROLE/defaults/main.yml
   ```

7. **Create Variable Validation Role**
   ```yaml
   # roles/posix_hardening_validation/tasks/validate_vars.yml
   - name: Validate admin_ip is set
     ansible.builtin.assert:
       that:
         - admin_ip is defined
         - admin_ip != ""
         - admin_ip is match('^[0-9.]+(/[0-9]+)?$')
       fail_msg: "admin_ip must be set to a valid IP or CIDR"

   - name: Validate ssh_allow_users is not empty
     ansible.builtin.assert:
       that:
         - ssh_allow_users is defined
         - ssh_allow_users | length > 0
       fail_msg: "ssh_allow_users cannot be empty (root login will be disabled)"
   ```

8. **Prefix Role Variables**
   ```yaml
   # roles/posix_hardening_ssh/defaults/main.yml
   posix_ssh_port: 22
   posix_ssh_allow_users: []
   posix_ssh_emergency_port: 2222
   ```

   This prevents variable name collisions across roles.

---

### 5. Task Organization and Idempotence

#### Current State

**Idempotence Issues:**

1. **Shell Module Overuse**

   Example from `site.yml`:
   ```yaml
   - name: Execute SSH hardening
     shell: |
       cd {{ toolkit_path }}
       sh scripts/01-ssh-hardening.sh
   ```

   Problems:
   - Runs every time (always shows "changed")
   - No way to detect actual changes
   - Cannot use `--check` mode effectively
   - Shell script may not be idempotent

2. **No changed_when Directives**

   For tasks that use `shell` or `command`:
   ```yaml
   - name: Check disk space
     shell: df -h / | awk 'NR==2 {print $4}'
     register: disk_space
     changed_when: false  # MISSING in many places
   ```

3. **No Creates/Removes Parameters**

   When running scripts:
   ```yaml
   - name: Create system snapshot
     shell: |
       cd {{ toolkit_path }}
       . ./config/defaults.conf
       create_system_snapshot "ansible_deploy_{{ snapshot_timestamp }}"
     # Should have: creates=/var/backups/snapshots/ansible_deploy_...
   ```

4. **Inline File Manipulation**
   ```yaml
   - name: Allow each user to use sudo without password
     lineinfile:
       path: "/etc/sudoers.d/{{ item }}"
       line: "{{ item }} ALL=(ALL) NOPASSWD:ALL"
       create: yes
       mode: '0440'
       validate: '/usr/sbin/visudo -cf %s'
   ```
   This is GOOD, but should be in a role, not inline in main playbook.

**Good Practices Found:**

- Use of `validate:` parameter for sudoers files
- Use of `wait_for_connection:` for connectivity checks
- Use of `assert:` for preflight validation
- Async tasks with polling for long operations
- Block/rescue for error handling (in `preflight.yml`)

**Recommendations:**

**HIGH PRIORITY:**

1. **Eliminate Shell Module for Configuration Management**

   Replace shell-based hardening with native modules:

   **SSH Hardening (replace scripts/01-ssh-hardening.sh):**
   ```yaml
   # roles/posix_hardening_ssh/tasks/main.yml
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
       - { regexp: '^#?Port', line: 'Port {{ posix_ssh_port }}' }
     notify: restart sshd

   # ALTERNATIVE: Use template for entire sshd_config
   - name: Deploy hardened SSH configuration
     ansible.builtin.template:
       src: sshd_config.j2
       dest: /etc/ssh/sshd_config
       owner: root
       group: root
       mode: '0600'
       validate: '/usr/sbin/sshd -t -f %s'
       backup: yes
     notify: restart sshd
   ```

   **Firewall (replace scripts/02-firewall-setup.sh):**
   ```yaml
   # Use ansible.posix.firewalld or ansible.builtin.iptables
   - name: Install iptables-persistent
     ansible.builtin.apt:
       name: iptables-persistent
       state: present
       update_cache: yes

   - name: Configure firewall rules
     ansible.builtin.iptables:
       chain: INPUT
       protocol: tcp
       destination_port: "{{ item }}"
       jump: ACCEPT
       comment: "Allow {{ item }}"
     loop: "{{ posix_firewall_allowed_ports }}"
     notify: save iptables rules

   # OR use template for /etc/iptables/rules.v4
   - name: Deploy iptables rules
     ansible.builtin.template:
       src: iptables.rules.j2
       dest: /etc/iptables/rules.v4
       owner: root
       group: root
       mode: '0600'
       backup: yes
     notify: reload iptables
   ```

   **Sysctl (replace scripts/14-sysctl-hardening.sh):**
   ```yaml
   - name: Apply kernel hardening parameters
     ansible.posix.sysctl:
       name: "{{ item.key }}"
       value: "{{ item.value }}"
       state: present
       sysctl_file: /etc/sysctl.d/99-hardening.conf
       reload: yes
     loop:
       - { key: 'net.ipv4.conf.all.accept_source_route', value: '0' }
       - { key: 'net.ipv4.conf.all.accept_redirects', value: '0' }
       - { key: 'net.ipv4.tcp_syncookies', value: '1' }
       - { key: 'kernel.dmesg_restrict', value: '1' }
     # Or loop_dict if using dictionary variable
   ```

2. **Add changed_when to All Shell/Command Tasks**
   ```yaml
   - name: Check if iptables is installed
     ansible.builtin.command: which iptables
     register: iptables_check
     changed_when: false  # Reading state, not changing
     failed_when: false

   - name: Verify iptables installation
     ansible.builtin.command: iptables --version
     register: iptables_version
     changed_when: false
   ```

3. **Use Stat Before File Operations**
   ```yaml
   - name: Check if toolkit exists
     ansible.builtin.stat:
       path: "{{ toolkit_path }}"
     register: toolkit_stat

   - name: Create toolkit directory
     ansible.builtin.file:
       path: "{{ toolkit_path }}"
       state: directory
       mode: '0755'
     when: not toolkit_stat.stat.exists
   ```

4. **Add Check Mode Support**
   ```yaml
   - name: Deploy configuration
     ansible.builtin.template:
       src: defaults.conf.j2
       dest: "{{ toolkit_path }}/config/defaults.conf"
     # This already supports --check mode automatically

   # For custom scripts
   - name: Run custom validation
     ansible.builtin.script: validate.sh
     when: not ansible_check_mode  # Skip in check mode
   ```

**MEDIUM PRIORITY:**

5. **Use register + when Instead of Ignoring Errors**
   ```yaml
   # Current (BAD)
   - name: Try to do something
     shell: some_command
     ignore_errors: yes

   # Better
   - name: Try to do something
     ansible.builtin.command: some_command
     register: result
     failed_when: false

   - name: Handle success case
     debug:
       msg: "Command succeeded"
     when: result.rc == 0

   - name: Handle failure case
     debug:
       msg: "Command failed, continuing anyway"
     when: result.rc != 0
   ```

6. **Use Block/Rescue for Complex Logic**
   ```yaml
   - name: SSH hardening with automatic rollback
     block:
       - name: Backup current config
         ansible.builtin.copy:
           src: /etc/ssh/sshd_config
           dest: /etc/ssh/sshd_config.{{ ansible_date_time.epoch }}
           remote_src: yes

       - name: Apply new config
         ansible.builtin.template:
           src: sshd_config.j2
           dest: /etc/ssh/sshd_config
           validate: '/usr/sbin/sshd -t -f %s'
         notify: restart sshd

       - name: Wait for SSH to be available
         ansible.builtin.wait_for_connection:
           timeout: 30

     rescue:
       - name: Restore backup on failure
         ansible.builtin.copy:
           src: /etc/ssh/sshd_config.{{ ansible_date_time.epoch }}
           dest: /etc/ssh/sshd_config
           remote_src: yes

       - name: Restart SSH with old config
         ansible.builtin.systemd:
           name: sshd
           state: restarted

       - name: Fail with descriptive message
         ansible.builtin.fail:
           msg: "SSH hardening failed, reverted to backup"
   ```

---

### 6. Handlers, Templates, and Files

#### Current State

**Handlers:**
- **NONE DEFINED** anywhere in the project
- All service restarts are inline in tasks
- Duplicate restart logic across playbooks

**Templates:**
- `templates/defaults.conf.j2` (136 lines) - Good, comprehensive
- `templates/firewall.conf.j2` (exists but not examined)
- Both templates are well-documented

**Files:**
- No static files in `files/` directory
- All files are copied from parent directory (`../scripts/`, `../lib/`)

**Issues:**

1. **No Handlers Directory**

   Every service restart is inline:
   ```yaml
   - name: Restart SSH service
     systemd:
       name: "{{ item }}"
       state: restarted
     loop:
       - ssh
       - sshd
     failed_when: false
   ```

   This means:
   - Restarts happen immediately, even if config hasn't changed
   - Cannot batch multiple config changes with single restart
   - Duplicate code across playbooks

2. **Templates Use Parent Directory References**
   ```yaml
   - name: Copy library files
     copy:
       src: "../lib/"
       dest: "{{ toolkit_path }}/lib/"
   ```

   This breaks if playbook is moved or run from different directory.

3. **No Template Variable Validation**

   Templates assume all variables are defined:
   ```jinja
   SSH_ALLOW_USERS="{{ ssh_allow_users }}"
   ```

   Should use defaults:
   ```jinja
   SSH_ALLOW_USERS="{{ ssh_allow_users | default('') }}"
   ```

**Recommendations:**

**HIGH PRIORITY:**

1. **Create Handlers in Roles**
   ```yaml
   # roles/posix_hardening_ssh/handlers/main.yml
   ---
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

   Usage in tasks:
   ```yaml
   - name: Configure SSH daemon
     ansible.builtin.lineinfile:
       path: /etc/ssh/sshd_config
       regexp: "{{ item.regexp }}"
       line: "{{ item.line }}"
     loop: "{{ ssh_config_lines }}"
     notify:
       - restart sshd
       - test ssh connectivity
   ```

2. **Move Files into Role Structure**
   ```
   roles/posix_hardening_deploy/
   ├── files/
   │   ├── lib/
   │   │   ├── common.sh
   │   │   ├── backup.sh
   │   │   └── ssh_safety.sh
   │   └── scripts/
   │       ├── 01-ssh-hardening.sh (if keeping)
   │       └── ...
   └── tasks/
       └── main.yml
   ```

   Then reference as:
   ```yaml
   - name: Copy library files
     ansible.builtin.copy:
       src: lib/
       dest: "{{ toolkit_path }}/lib/"
   ```

3. **Add Template Validation**
   ```jinja
   {# templates/defaults.conf.j2 #}

   {# Validate required variables #}
   {% if admin_ip is not defined or admin_ip == "" %}
   {{ fail("admin_ip must be defined") }}
   {% endif %}

   {% if ssh_allow_users is not defined or ssh_allow_users | length == 0 %}
   {{ fail("ssh_allow_users must be defined") }}
   {% endif %}

   # SSH Configuration
   SSH_ALLOW_USERS="{{ ssh_allow_users | join(' ') if ssh_allow_users is iterable else ssh_allow_users }}"
   ```

4. **Use ansible.builtin.template Instead of copy**
   ```yaml
   # BAD - static file, no variable substitution
   - name: Deploy config
     ansible.builtin.copy:
       src: config.conf
       dest: /etc/myapp/config.conf

   # GOOD - template with variables
   - name: Deploy config
     ansible.builtin.template:
       src: config.conf.j2
       dest: /etc/myapp/config.conf
   ```

**MEDIUM PRIORITY:**

5. **Create Handler Chain for Firewall**
   ```yaml
   # roles/posix_hardening_firewall/handlers/main.yml
   - name: save iptables rules
     ansible.builtin.shell: iptables-save > /etc/iptables/rules.v4
     listen: "save iptables"

   - name: reload iptables
     ansible.builtin.shell: iptables-restore < /etc/iptables/rules.v4
     listen: "reload iptables"

   - name: test network connectivity
     ansible.builtin.wait_for:
       port: 22
       host: "{{ ansible_host }}"
       timeout: 10
     delegate_to: localhost
     listen: "test firewall"
   ```

6. **Use Ansible File Lookup for Small Files**
   ```yaml
   - name: Deploy public SSH key
     ansible.builtin.authorized_key:
       user: root
       key: "{{ lookup('file', 'team_keys/ansible_ed25519.pub') }}"
   ```

---

### 7. Documentation Within Ansible Files

#### Current State

**Good Practices:**
- Excellent inline comments in playbooks
- Clear task names
- Descriptive debug messages
- Header blocks in templates with generation info

**Issues:**

1. **Inconsistent Commenting Style**
   - Some tasks have explanatory comments above
   - Others rely only on task names
   - No standardized format

2. **No Role Documentation**
   - Because roles don't exist yet

3. **Variable Documentation Only in group_vars**
   - Good that it exists
   - But should also be in role defaults

**Recommendations:**

**HIGH PRIORITY:**

1. **Adopt Consistent Comment Style**
   ```yaml
   # ==============================================================================
   # SSH Hardening Configuration
   # ==============================================================================
   # Purpose: Configure SSH daemon for security best practices
   # Impact: Will disable root login and password authentication
   # Rollback: Backup is created, restore with rescue block
   # ==============================================================================

   - name: Backup SSH configuration
     ansible.builtin.copy:
       src: /etc/ssh/sshd_config
       dest: /etc/ssh/sshd_config.backup
       remote_src: yes
     tags: [ssh, backup]

   # Disable root login (CRITICAL for security)
   - name: Disable root login
     ansible.builtin.lineinfile:
       path: /etc/ssh/sshd_config
       regexp: '^#?PermitRootLogin'
       line: 'PermitRootLogin no'
   ```

2. **Document Each Role**
   ```markdown
   # roles/posix_hardening_ssh/README.md

   # SSH Hardening Role

   ## Purpose
   Hardens SSH daemon configuration according to security best practices.

   ## Variables

   ### Required
   - `posix_ssh_allow_users` (list): Users allowed to SSH
   - `admin_ip` (string): Management IP for firewall whitelist

   ### Optional
   - `posix_ssh_port` (int): SSH port (default: 22)
   - `posix_ssh_permit_root_login` (bool): Allow root login (default: false)

   ## Example Playbook
   ```yaml
   - hosts: all
     roles:
       - role: posix_hardening_ssh
         posix_ssh_allow_users:
           - admin
           - deploy
   ```

   ## Dependencies
   - posix_hardening_users (creates users before SSH config)

   ## Handlers
   - `restart sshd`: Restarts SSH daemon
   - `test ssh connectivity`: Validates SSH access after restart
   ```

**MEDIUM PRIORITY:**

3. **Add Meta Information to Playbooks**
   ```yaml
   ---
   # ==============================================================================
   # POSIX Hardening Deployment Playbook
   # ==============================================================================
   # Purpose: Deploy and execute POSIX hardening toolkit
   #
   # Requirements:
   #   - Debian-based target systems
   #   - SSH access with sudo privileges
   #   - admin_ip variable set
   #
   # Safety:
   #   - Creates backup snapshots before changes
   #   - Emergency SSH port for recovery
   #   - Automatic rollback on failure
   #
   # Usage:
   #   ansible-playbook site.yml -i inventories/production
   #   ansible-playbook site.yml --tags priority1 (critical only)
   #   ansible-playbook site.yml -e dry_run=1 (test mode)
   #
   # Author: POSIX Hardening Team
   # Version: 1.0.0
   # ==============================================================================

   - name: POSIX Hardening Deployment
     hosts: all
     # ...
   ```

---

### 8. Testing Strategy

#### Current State

**Testing Infrastructure:**
```
ansible/testing/
├── Dockerfile
├── docker-compose.yml
├── inventory-docker.ini
├── test-runner.sh
└── README.md (comprehensive)
```

**Good Practices:**
- Docker-based testing environment
- Isolated test containers
- Automated test runner script
- Documentation for testing

**Issues:**

1. **No Molecule Tests**
   - Molecule is the standard Ansible testing framework
   - Not present in this project

2. **No ansible-lint Configuration**
   - No `.ansible-lint` file
   - No linting in CI/CD pipeline

3. **No Automated Validation Tests**
   - Manual validation only
   - No test assertions for hardening state

4. **No CI/CD Integration**
   - No GitHub Actions / GitLab CI
   - Tests must be run manually

5. **Test Coverage Unclear**
   - What scenarios are tested?
   - What edge cases are covered?

**Recommendations:**

**HIGH PRIORITY:**

1. **Add ansible-lint Configuration**
   ```yaml
   # .ansible-lint
   ---
   profile: production

   exclude_paths:
     - .cache/
     - .github/
     - ansible/retry/
     - ansible/testing/

   skip_list:
     - 'yaml[line-length]'  # Allow long lines for readability
     - 'no-changed-when'    # Will fix gradually

   warn_list:
     - experimental
     - role-name

   # Enable offline mode (no internet required)
   offline: false

   # Use strict mode for production
   strict: true
   ```

   Run with:
   ```bash
   ansible-lint ansible/playbooks/*.yml
   ansible-lint ansible/roles/
   ```

2. **Integrate into Pre-Commit Hook**
   ```yaml
   # .pre-commit-config.yaml
   repos:
     - repo: https://github.com/ansible/ansible-lint
       rev: v6.22.1
       hooks:
         - id: ansible-lint
           args: [--profile=production]
           files: \.(yaml|yml)$
   ```

3. **Add Syntax Check to CI**
   ```yaml
   # .github/workflows/ansible-ci.yml
   name: Ansible CI

   on:
     push:
       paths:
         - 'ansible/**'
     pull_request:
       paths:
         - 'ansible/**'

   jobs:
     lint:
       runs-on: ubuntu-latest
       steps:
         - uses: actions/checkout@v3

         - name: Set up Python
           uses: actions/setup-python@v4
           with:
             python-version: '3.10'

         - name: Install dependencies
           run: |
             pip install ansible ansible-lint

         - name: Run ansible-lint
           run: |
             cd ansible
             ansible-lint playbooks/*.yml

         - name: Syntax check
           run: |
             cd ansible
             ansible-playbook --syntax-check playbooks/site.yml

     test:
       runs-on: ubuntu-latest
       needs: lint
       steps:
         - uses: actions/checkout@v3

         - name: Test with Docker
           run: |
             cd ansible/testing
             ./test-runner.sh full
   ```

**MEDIUM PRIORITY:**

4. **Add Molecule Tests for Roles**
   ```bash
   # Install molecule
   pip install molecule molecule-docker ansible-lint

   # Initialize molecule in a role
   cd ansible/roles/posix_hardening_ssh
   molecule init scenario
   ```

   Create test scenario:
   ```yaml
   # roles/posix_hardening_ssh/molecule/default/molecule.yml
   ---
   driver:
     name: docker

   platforms:
     - name: debian-11
       image: debian:11
       pre_build_image: true

   provisioner:
     name: ansible
     config_options:
       defaults:
         callbacks_enabled: profile_tasks
     playbooks:
       converge: converge.yml
       verify: verify.yml

   verifier:
     name: ansible
   ```

   Verification tests:
   ```yaml
   # roles/posix_hardening_ssh/molecule/default/verify.yml
   ---
   - name: Verify SSH hardening
     hosts: all
     tasks:
       - name: Check SSH config
         ansible.builtin.shell: |
           grep -q "^PermitRootLogin no" /etc/ssh/sshd_config
         changed_when: false

       - name: Verify SSH is running
         ansible.builtin.systemd:
           name: sshd
           state: started
         check_mode: yes
         register: ssh_status

       - name: Assert SSH is running
         ansible.builtin.assert:
           that:
             - ssh_status.status.ActiveState == 'active'
   ```

5. **Create Test Inventory with Test Cases**
   ```yaml
   # ansible/tests/test_inventory.yml
   ---
   all:
     children:
       test_debian_11:
         hosts:
           debian11-test:
             ansible_connection: docker
             ansible_host: debian11_container

       test_ubuntu_22:
         hosts:
           ubuntu22-test:
             ansible_connection: docker
             ansible_host: ubuntu22_container

     vars:
       admin_ip: "127.0.0.1"
       ssh_allow_users:
         - testuser
       dry_run: true
   ```

6. **Add Validation Assertions**
   ```yaml
   # roles/posix_hardening_validation/tasks/main.yml
   ---
   - name: Check SSH configuration
     ansible.builtin.shell: |
       grep "^PermitRootLogin no" /etc/ssh/sshd_config
     register: ssh_root_login
     changed_when: false
     failed_when: ssh_root_login.rc != 0

   - name: Verify firewall is active
     ansible.builtin.command: iptables -L
     register: iptables_list
     changed_when: false
     failed_when: "'INPUT' not in iptables_list.stdout"

   - name: Check kernel parameters
     ansible.posix.sysctl:
       name: "{{ item.key }}"
       value: "{{ item.value }}"
     loop:
       - { key: 'net.ipv4.conf.all.accept_source_route', value: '0' }
       - { key: 'net.ipv4.tcp_syncookies', value: '1' }
     check_mode: yes
     register: sysctl_check

   - name: Assert all checks passed
     ansible.builtin.assert:
       that:
         - ssh_root_login.rc == 0
         - "'INPUT' in iptables_list.stdout"
       success_msg: "All validation checks passed"
       fail_msg: "Some validation checks failed"
   ```

---

## Proposed New Structure

Based on all recommendations, here's the **target structure**:

```
ansible/
├── ansible.cfg
├── .ansible-lint
├── collections/
│   └── requirements.yml
│
├── inventories/
│   ├── production/
│   │   ├── hosts.yml
│   │   └── group_vars/
│   │       ├── all.yml
│   │       └── vault.yml (encrypted)
│   ├── staging/
│   │   ├── hosts.yml
│   │   └── group_vars/
│   │       ├── all.yml
│   │       └── vault.yml
│   └── testing/
│       └── hosts.yml
│
├── playbooks/
│   ├── site.yml (orchestrator - calls roles)
│   ├── preflight.yml
│   ├── rollback.yml
│   └── validate.yml
│
├── roles/
│   ├── posix_hardening_deploy/
│   │   ├── tasks/main.yml
│   │   ├── files/
│   │   │   ├── lib/
│   │   │   └── scripts/
│   │   ├── templates/
│   │   │   └── defaults.conf.j2
│   │   ├── defaults/main.yml
│   │   └── README.md
│   │
│   ├── posix_hardening_users/
│   │   ├── tasks/main.yml
│   │   ├── defaults/main.yml
│   │   └── README.md
│   │
│   ├── posix_hardening_ssh/
│   │   ├── tasks/main.yml
│   │   ├── handlers/main.yml
│   │   ├── templates/
│   │   │   └── sshd_config.j2
│   │   ├── defaults/main.yml
│   │   ├── meta/main.yml
│   │   ├── README.md
│   │   └── molecule/
│   │       └── default/
│   │           ├── molecule.yml
│   │           ├── converge.yml
│   │           └── verify.yml
│   │
│   ├── posix_hardening_firewall/
│   │   ├── tasks/main.yml
│   │   ├── handlers/main.yml
│   │   ├── templates/
│   │   │   └── iptables.rules.j2
│   │   ├── defaults/main.yml
│   │   └── README.md
│   │
│   ├── posix_hardening_kernel/
│   │   ├── tasks/main.yml
│   │   ├── handlers/main.yml
│   │   ├── templates/
│   │   │   └── 99-hardening.conf.j2
│   │   ├── defaults/main.yml
│   │   └── README.md
│   │
│   └── posix_hardening_validation/
│       ├── tasks/main.yml
│       ├── tasks/validate_vars.yml
│       ├── defaults/main.yml
│       └── README.md
│
├── group_vars/
│   └── all.yml (shared across all environments)
│
├── utils/
│   ├── generate-inventory.sh
│   └── inventory-config.yml
│
├── testing/
│   ├── docker-compose.yml
│   ├── test-runner.sh
│   └── README.md
│
├── .gitignore
└── README.md
```

### Key Changes:
1. Playbooks moved to `playbooks/` subdirectory
2. Roles created for each major component
3. Inventory organized by environment
4. Handlers defined in each role
5. Templates organized within roles
6. Testing infrastructure with molecule
7. Secrets managed with Ansible Vault

---

## Migration Plan

### Phase 1: Foundation (Week 1)
- [ ] Create role directory structure
- [ ] Move templates into role templates/
- [ ] Create handler files
- [ ] Set up inventory/ directory structure
- [ ] Update .gitignore

### Phase 2: Role Extraction (Week 2-3)
- [ ] Create posix_hardening_users role
- [ ] Create posix_hardening_ssh role
- [ ] Create posix_hardening_firewall role
- [ ] Create posix_hardening_deploy role
- [ ] Update site.yml to use roles

### Phase 3: Testing Infrastructure (Week 4)
- [ ] Add ansible-lint configuration
- [ ] Set up molecule tests
- [ ] Create CI/CD pipeline
- [ ] Add validation assertions

### Phase 4: Variables and Secrets (Week 5)
- [ ] Standardize boolean formats
- [ ] Convert string lists to arrays
- [ ] Implement Ansible Vault
- [ ] Add variable validation

### Phase 5: Documentation (Week 6)
- [ ] Write role README files
- [ ] Document variable precedence
- [ ] Create migration guide
- [ ] Update main README

---

## Quick Wins (Implement Immediately)

These can be done without major refactoring:

1. **Add .gitignore entries:**
   ```gitignore
   ansible/retry/
   *.retry
   ansible/ansible.log
   ansible/inventory-generated.ini.backup.*
   ```

2. **Add handlers to site.yml:**
   ```yaml
   handlers:
     - name: restart sshd
       ansible.builtin.systemd:
         name: sshd
         state: restarted
   ```

3. **Add changed_when to shell tasks:**
   ```yaml
   - name: Check disk space
     shell: df -h / | awk 'NR==2 {print $4}'
     register: disk_space
     changed_when: false  # Add this line
   ```

4. **Add ansible-lint:**
   ```bash
   pip install ansible-lint
   ansible-lint ansible/site.yml
   ```

5. **Create collections/requirements.yml:**
   ```yaml
   ---
   collections:
     - name: ansible.posix
     - name: community.general
   ```

6. **Update ansible.cfg:**
   ```ini
   [defaults]
   collections_paths = ./collections
   vault_password_file = ~/.ansible/vault_pass.txt
   ```

---

## Conclusion

The POSIX-hardening Ansible deployment shows strong security awareness and good operational practices. The main areas for improvement are:

1. **Structural**: Adopt role-based architecture
2. **Idempotence**: Replace shell scripts with native Ansible modules
3. **Testing**: Add molecule tests and ansible-lint
4. **Secrets**: Implement Ansible Vault
5. **Documentation**: Add role README files

The migration can be done incrementally without disrupting current operations. Start with quick wins, then gradually refactor into roles over 4-6 weeks.

**Estimated Effort:**
- Quick wins: 2-4 hours
- Full migration: 40-60 hours
- Testing and validation: 20-30 hours
- **Total: 60-90 hours (2-3 weeks for one person)**

**Risk Level:** Low (if done incrementally with testing at each step)

**Benefit:** High (improved maintainability, testability, reusability)

---

## References

- [Ansible Best Practices](https://docs.ansible.com/ansible/latest/tips_tricks/ansible_tips_tricks.html)
- [Ansible Roles](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_reuse_roles.html)
- [Molecule Testing](https://molecule.readthedocs.io/)
- [Ansible Lint](https://ansible.readthedocs.io/projects/lint/)
- [Ansible Vault](https://docs.ansible.com/ansible/latest/vault_guide/index.html)

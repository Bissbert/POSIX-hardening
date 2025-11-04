# Banner Role - Usage Examples

## Quick Start

### 1. Basic Usage (Default Settings)

```yaml
- hosts: all
  become: true
  roles:
    - posix_hardening_banner
```

This creates standard warning banners with placeholder organization info.

### 2. Customize Organization

```yaml
- hosts: all
  become: true
  roles:
    - role: posix_hardening_banner
      vars:
        posix_banner_organization: "Acme Corporation"
        posix_banner_contact: "security@acme.com"
```

### 3. Force Re-apply

```yaml
- hosts: all
  become: true
  roles:
    - role: posix_hardening_banner
      vars:
        posix_banner_force_reharden: true
```

## Advanced Customization

### Custom Warning Text

```yaml
- hosts: production
  become: true
  roles:
    - role: posix_hardening_banner
      vars:
        posix_banner_organization: "SecureCorp"
        posix_banner_contact: "security@securecorp.com"
        posix_banner_warning_text: |
          This system contains confidential and proprietary information.
          Unauthorized access, use, or disclosure is strictly prohibited
          and may result in criminal and/or civil prosecution.
          All access is monitored, logged, and recorded.
        posix_banner_warning_footer: |
          By accessing this system, you acknowledge that you have read
          and understood this warning and agree to comply with all
          applicable policies and laws. Disconnect NOW if unauthorized.
```

### Simple Banners (No Decorations)

```yaml
- hosts: all
  become: true
  roles:
    - role: posix_hardening_banner
      vars:
        posix_banner_use_decorations: false
        posix_banner_organization: "TechCo"
        posix_banner_contact: "admin@techco.com"
```

Output:

```text
AUTHORIZED ACCESS ONLY
======================

Unauthorized access to this system is strictly prohibited.
All activities are monitored and logged.
...
```

### Custom Decorations

```yaml
- hosts: all
  become: true
  roles:
    - role: posix_hardening_banner
      vars:
        posix_banner_decoration_char: "*"
        posix_banner_decoration_width: 70
        posix_banner_organization: "StarCorp"
```

Output:

```text
**********************************************************************
*                      AUTHORIZED ACCESS ONLY                       *
**********************************************************************
```

### Disable Specific Banners

```yaml
# Only MOTD, no pre-login banners
- hosts: dev_servers
  become: true
  roles:
    - role: posix_hardening_banner
      vars:
        posix_banner_enable_issue: false
        posix_banner_enable_issue_net: false
        posix_banner_enable_motd: true
```

```yaml
# Only pre-login banners, no MOTD
- hosts: prod_servers
  become: true
  roles:
    - role: posix_hardening_banner
      vars:
        posix_banner_enable_issue: true
        posix_banner_enable_issue_net: true
        posix_banner_enable_motd: false
```

### Custom MOTD Only

```yaml
- hosts: all
  become: true
  roles:
    - role: posix_hardening_banner
      vars:
        posix_banner_enable_issue: false
        posix_banner_enable_issue_net: false
        posix_banner_enable_motd: true
        posix_banner_custom_motd: |
          ===================================
          Welcome to {{ ansible_hostname }}
          ===================================

          Environment: Production
          Support: ops@example.com
          Emergency: +1-555-0911

          All activity is monitored and logged.
          Unauthorized access is prohibited.
          ===================================
```

### Add Custom Text to All Banners

```yaml
- hosts: all
  become: true
  roles:
    - role: posix_hardening_banner
      vars:
        posix_banner_organization: "GlobalTech"
        posix_banner_contact: "security@globaltech.com"
        posix_banner_custom_text: |

          For access requests: access@globaltech.com
          For security incidents: incident@globaltech.com
          Emergency hotline: +1-800-SEC-HELP
```

### Different Banners for Different Environments

```yaml
# In group_vars/production.yml
posix_banner_organization: "Acme Corp - Production"
posix_banner_contact: "production-security@acme.com"
posix_banner_warning_text: |
  !!!!! PRODUCTION SYSTEM !!!!!
  This is a production system. Unauthorized access is prohibited.
  All activities are monitored, logged, and audited.
  Any unauthorized access will be prosecuted to the fullest extent.

# In group_vars/development.yml
posix_banner_organization: "Acme Corp - Development"
posix_banner_contact: "dev-team@acme.com"
posix_banner_warning_text: |
  DEVELOPMENT ENVIRONMENT
  Authorized developers only.
  All activities are logged for audit purposes.

# In playbook
- hosts: all
  become: true
  roles:
    - posix_hardening_banner
```

## Validation Examples

### Run with Validation Only

```bash
# Run just validation phase (if already applied)
ansible-playbook site.yml --tags validate --extra-vars "posix_banner_force_reharden=true"
```

### Skip Validation

```yaml
- hosts: all
  become: true
  roles:
    - role: posix_hardening_banner
      vars:
        posix_banner_validate_after_apply: false
```

### Disable Backups

```yaml
- hosts: all
  become: true
  roles:
    - role: posix_hardening_banner
      vars:
        posix_banner_backup_before_changes: false
```

## Tag-Based Execution

### Apply Only Issue Banner

```bash
ansible-playbook site.yml --tags issue
```

### Apply Only MOTD

```bash
ansible-playbook site.yml --tags motd
```

### Skip Validation

```bash
ansible-playbook site.yml --skip-tags validate
```

### Check Mode (Dry Run)

```bash
ansible-playbook site.yml --check --diff
```

## Integration Examples

### With Other Hardening Roles

```yaml
- hosts: all
  become: true

  roles:
    # Apply SSH hardening first
    - role: posix_hardening_ssh
      vars:
        posix_ssh_banner_file: /etc/issue.net

    # Then configure banners
    - role: posix_hardening_banner
      vars:
        posix_banner_organization: "SecureCorp"
        posix_banner_contact: "security@securecorp.com"

    # Finally validate
    - posix_hardening_validation
```

### Environment-Specific with Ansible Vault

```yaml
# Store sensitive contact info in vault
# In group_vars/all/vault.yml (encrypted)
vault_banner_contact: "security-team@secret-company.com"
vault_banner_organization: "Secret Government Agency"

# In playbook
- hosts: all
  become: true
  roles:
    - role: posix_hardening_banner
      vars:
        posix_banner_organization: "{{ vault_banner_organization }}"
        posix_banner_contact: "{{ vault_banner_contact }}"
```

### Conditional Based on Compliance Framework

```yaml
- hosts: all
  become: true

  pre_tasks:
    - name: Set banner variables based on compliance framework
      set_fact:
        banner_config: >-
          {{
            (compliance_framework == 'pci-dss') | ternary(
              {
                'warning': 'PCI-DSS Compliant System - Authorized Access Only',
                'org': 'Payment Processing Division'
              },
              (compliance_framework == 'hipaa') | ternary(
                {
                  'warning': 'HIPAA Protected System - Authorized Personnel Only',
                  'org': 'Healthcare Data Division'
                },
                {
                  'warning': 'Corporate System - Authorized Access Only',
                  'org': 'General IT'
                }
              )
            )
          }}

  roles:
    - role: posix_hardening_banner
      vars:
        posix_banner_warning_title: "{{ banner_config.warning }}"
        posix_banner_organization: "{{ banner_config.org }}"
```

## Testing

### Test in Vagrant

```bash
# Vagrantfile
Vagrant.configure("2") do |config|
  config.vm.box = "ubuntu/jammy64"

  config.vm.provision "ansible" do |ansible|
    ansible.playbook = "test_banner.yml"
    ansible.extra_vars = {
      posix_banner_organization: "Test Lab",
      posix_banner_contact: "admin@localhost"
    }
  end
end

# test_banner.yml
- hosts: all
  become: true
  roles:
    - posix_hardening_banner
```

### Test in Docker

```bash
# Test banner generation
docker run -d --name test-banner ubuntu:22.04 sleep 3600
ansible-playbook -i "test-banner," -c docker site.yml
docker exec test-banner cat /etc/issue
docker exec test-banner cat /etc/motd
docker rm -f test-banner
```

## Troubleshooting

### Banner Not Showing on SSH

```yaml
# Ensure SSH is configured to show banner
- hosts: all
  become: true

  tasks:
    - name: Configure SSH to display banner
      lineinfile:
        path: /etc/ssh/sshd_config
        regexp: '^#?Banner'
        line: 'Banner /etc/issue.net'
        state: present
      notify: restart sshd

    - name: Apply banner role
      include_role:
        name: posix_hardening_banner

  handlers:
    - name: restart sshd
      service:
        name: sshd
        state: restarted
```

### MOTD Not Showing

```yaml
# Disable dynamic MOTD on Ubuntu/Debian
- hosts: ubuntu_servers
  become: true

  pre_tasks:
    - name: Disable dynamic MOTD scripts
      file:
        path: "/etc/update-motd.d/{{ item }}"
        mode: "0644"
      loop:
        - 00-header
        - 10-help-text
        - 50-motd-news
      ignore_errors: true

  roles:
    - posix_hardening_banner
```

## Real-World Example

Complete example for a production environment:

```yaml
# File: site.yml
---
- name: Configure Security Banners
  hosts: all
  become: true
  gather_facts: true

  vars:
    # Different banners for different server types
    banner_configs:
      web:
        org: "Acme Corp - Web Services"
        contact: "web-security@acme.com"
        warning: |
          This web server contains customer data and must be protected.
          Unauthorized access will be prosecuted.
      database:
        org: "Acme Corp - Database Services"
        contact: "db-security@acme.com"
        warning: |
          This database server contains sensitive financial information.
          Unauthorized access will result in immediate termination and prosecution.
      app:
        org: "Acme Corp - Application Services"
        contact: "app-security@acme.com"
        warning: |
          This application server handles business-critical operations.
          All access is monitored and recorded.

  tasks:
    - name: Determine server type
      set_fact:
        server_type: "{{ group_names | select('match', '^(web|database|app)$') | first | default('app') }}"

    - name: Apply banner configuration
      include_role:
        name: posix_hardening_banner
      vars:
        posix_banner_organization: "{{ banner_configs[server_type].org }}"
        posix_banner_contact: "{{ banner_configs[server_type].contact }}"
        posix_banner_warning_text: "{{ banner_configs[server_type].warning }}"
        posix_banner_custom_text: |

          Server: {{ ansible_hostname }}
          Environment: {{ env | default('production') }}
          Last Updated: {{ ansible_date_time.date }}
```

# Emergency Recovery Procedures

## Problem: "sorry, you must have a tty to run sudo"

If Ansible is failing with this error after running the hardening scripts, you need to fix the `requiretty` setting.

---

## Quick Fix Methods

### Method 1: One-Liner (Fastest)

If you can SSH to the server, run this single command:

```bash
ssh -t user@server 'sudo sed -i.backup "s/^Defaults requiretty$/Defaults !requiretty/" /etc/sudoers.d/hardening && echo "Fixed!" || echo "Failed"'
```

**Replace:**
- `user` with your SSH username
- `server` with your server hostname/IP

The `-t` flag forces TTY allocation, which allows sudo to work this one time.

---

### Method 2: Recovery Script (Recommended)

1. **Copy the recovery script to the server:**
   ```bash
   scp scripts/recovery/fix-sudo-requiretty.sh user@server:/tmp/
   ```

2. **SSH with TTY and run it:**
   ```bash
   ssh -t user@server 'sudo /tmp/fix-sudo-requiretty.sh'
   ```

---

### Method 3: Manual Fix via SSH

If you can SSH to the server:

```bash
# SSH with forced TTY allocation
ssh -t user@server

# Once connected, run:
sudo sed -i.backup 's/^Defaults requiretty$/Defaults !requiretty/' /etc/sudoers.d/hardening

# Verify the change:
grep requiretty /etc/sudoers.d/hardening
```

You should see: `Defaults !requiretty`

---

### Method 4: Console/IPMI Access

If you have physical or IPMI/KVM access:

1. **Login to the server console**
2. **Become root:**
   ```bash
   sudo -i
   # or
   su -
   ```

3. **Edit the sudoers file:**
   ```bash
   sed -i.backup 's/^Defaults requiretty$/Defaults !requiretty/' /etc/sudoers.d/hardening
   ```

4. **Verify:**
   ```bash
   grep requiretty /etc/sudoers.d/hardening
   visudo -c -f /etc/sudoers.d/hardening
   ```

---

### Method 5: Ansible Ad-Hoc Command

If you still have working Ansible access with a different user or can use `become_flags`:

```bash
ansible all -i inventory.ini -m shell \
  -a "sed -i.backup 's/^Defaults requiretty$/Defaults !requiretty/' /etc/sudoers.d/hardening" \
  --become --become-method=su
```

Or with raw module:

```bash
ansible all -i inventory.ini -m raw \
  -a "sed -i.backup 's/^Defaults requiretty$/Defaults !requiretty/' /etc/sudoers.d/hardening" \
  --become
```

---

## Verification

After applying any fix, verify it worked:

### Test 1: Check the file
```bash
grep requiretty /etc/sudoers.d/hardening
```

Should show: `Defaults !requiretty`

### Test 2: Test sudo without TTY
```bash
ssh user@server 'sudo -n whoami'
```

Should return: `root` (or work without error)

### Test 3: Run Ansible
```bash
ansible -i inventory.ini server -m ping
```

Should succeed with `pong`.

---

## Prevention for New Servers

For servers you haven't hardened yet, the latest version of the toolkit already includes this fix. Simply pull the latest changes:

```bash
cd POSIX-hardening
git pull
```

Then deploy normally - `requiretty` will be disabled by default.

---

## Understanding the Fix

**What changed:**
- **Before:** `Defaults requiretty` (requires terminal)
- **After:** `Defaults !requiretty` (no terminal required)

**Why:**
- `requiretty` is a legacy security measure
- Modern sudo has better controls (timeouts, logging, etc.)
- Automation tools like Ansible can't provide TTY
- The fix maintains all other security hardening

**Security note:** If you need stricter control, you can enable requiretty per-user:
```bash
# In /etc/sudoers.d/hardening:
Defaults requiretty                    # Enable for all users
Defaults:ansible_user !requiretty     # Except automation user
```

---

## Multiple Servers Recovery

### Using Ansible Loop

Create a recovery playbook `fix-sudo-tty.yml`:

```yaml
---
- name: Emergency fix for sudo requiretty
  hosts: all
  gather_facts: no
  tasks:
    - name: Fix requiretty in sudoers
      raw: |
        sed -i.backup 's/^Defaults requiretty$/Defaults !requiretty/' /etc/sudoers.d/hardening && \
        visudo -c -f /etc/sudoers.d/hardening
      become: yes
      become_flags: '-i'  # Force interactive shell to get TTY
```

Run with:
```bash
ansible-playbook -i inventory.ini fix-sudo-tty.yml
```

### Using Parallel SSH (pssh)

If you have `pssh` installed:

```bash
parallel-ssh -i -h hosts.txt -t 0 \
  "sudo sed -i.backup 's/^Defaults requiretty$/Defaults !requiretty/' /etc/sudoers.d/hardening"
```

### Using a Bash Loop

```bash
#!/bin/bash
SERVERS="server1 server2 server3"

for server in $SERVERS; do
    echo "Fixing $server..."
    ssh -t user@$server 'sudo sed -i.backup "s/^Defaults requiretty$/Defaults !requiretty/" /etc/sudoers.d/hardening'
    echo "Done: $server"
done
```

---

## Troubleshooting

### "Permission denied" even with -t flag

Try using `su` instead:
```bash
ssh -t user@server
su -  # Enter root password
sed -i.backup 's/^Defaults requiretty$/Defaults !requiretty/' /etc/sudoers.d/hardening
```

### "visudo: /etc/sudoers.d/hardening: bad permissions"

Fix permissions:
```bash
sudo chmod 440 /etc/sudoers.d/hardening
sudo chown root:root /etc/sudoers.d/hardening
```

### "No such file or directory: /etc/sudoers.d/hardening"

The hardening may not have been applied. Check:
```bash
ls -la /etc/sudoers.d/
grep requiretty /etc/sudoers
```

### Still getting "must have tty" after fix

Check all sudoers files:
```bash
grep -r "requiretty" /etc/sudoers /etc/sudoers.d/
```

Remove or fix any other instances.

---

## Contact & Support

If none of these methods work, you likely need:
1. Physical/console access to the server
2. IPMI/iLO/iDRAC remote console access
3. Recovery mode boot

The backup file is always created at:
```
/etc/sudoers.d/hardening.backup-YYYYMMDD-HHMMSS
```

You can restore from backup if needed:
```bash
sudo cp /etc/sudoers.d/hardening.backup-20251021-065558 /etc/sudoers.d/hardening
```

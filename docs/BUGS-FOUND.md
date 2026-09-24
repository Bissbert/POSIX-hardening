# Bugs found while documenting this toolkit

[← back to the documentation index](README.md)

This file was written during a documentation pass, before any of it was
fixed. Each entry records the defect as it was found, with the reproduction
and the diff proposed at the time.

**Status.** An independent adjudication confirmed 22 of the 24 entries,
rejected BUG-10 and left BUG-20 unresolved for want of an isolated OpenSSH
target. A fix pass then fixed 15 of them on the default branch. The other
seven were deferred because each needs a design decision, not a patch. The
status column below and the status line under each heading give the current
state. For a fixed entry, the "Verified" transcript shows the behaviour
before the fix, and the committed fix may differ from the diff proposed here.
The captures in [`media/captures/`](../media/captures) have since been
re-recorded against the default branch.

Each entry says what was **verified** by running it and what was **inferred**
by reading the code. Every reproduction runs in a throwaway Debian 12 container:
the hardening runs in one built from `ansible/testing/Dockerfile`, and the
read-only checks of the repository and the Ansible tree in the analysis and
host-tools containers. The
tools that reproduce every entry are in [`tools/`](../tools) and their raw
output is in [`media/captures/`](../media/captures).

Several entries turn on POSIX shell semantics rather than on this toolkit:
pipeline subshells, `break` across them, `||` versus pipeline precedence, and
the dynamic scope of `local`. `tools/shell-semantics-demo.sh` demonstrates each
of them in `dash`, `bash` and `busybox sh` in isolation, so those claims can be
checked without reading any of the toolkit's code; its output is
[`media/captures/shell-semantics.txt`](../media/captures/shell-semantics.txt).

The severity column is this pass's own judgement, not the project's.

| ID | File | Severity | Status | One line |
|---|---|---|---|---|
| [BUG-1](#bug-1) | `lib/rollback.sh:8`, `lib/ssh_safety.sh:8` | Blocking | Fixed in [`77b3632`](https://github.com/Bissbert/POSIX-hardening/commit/77b3632) | Every documented entry point aborts before doing any work |
| [BUG-2](#bug-2) | `emergency-rollback.sh:14` | Blocking | Fixed in [`a25ce32`](https://github.com/Bissbert/POSIX-hardening/commit/a25ce32) | The emergency tool aborts on its second statement |
| [BUG-3](#bug-3) | `lib/common.sh:73`, `:222`, `lib/backup.sh:61`, `lib/ssh_safety.sh:95` | Critical | Fixed in [`50f241d`](https://github.com/Bissbert/POSIX-hardening/commit/50f241d) | Backup paths are captured with a log line glued to the front, so rollback restores nothing |
| [BUG-4](#bug-4) | `lib/rollback.sh:18` | High | Open, needs a decision | Without `config/defaults.conf`, automatic rollback is silently disabled |
| [BUG-5](#bug-5) | `lib/rollback.sh:102` | Medium | Fixed in [`7726958`](https://github.com/Bissbert/POSIX-hardening/commit/7726958) | `rollback_transaction` reports success after every action in it failed |
| [BUG-6](#bug-6) | `scripts/03-kernel-params.sh:121` | Medium | Fixed in [`4b7a0b4`](https://github.com/Bissbert/POSIX-hardening/commit/4b7a0b4) | One unsupported sysctl key aborts the script with no indication which |
| [BUG-7](#bug-7) | `orchestrator.sh:11-17` | Blocking | Open, needs a decision | With a `config/defaults.conf` present, the orchestrator cannot start at all |
| [BUG-8](#bug-8) | `orchestrator.sh:342` | Blocking | Open, needs a decision | `--dry-run` aborts on a read-only variable |
| [BUG-9](#bug-9) | `orchestrator.sh:56-64`, `:187`, `:139` | High | Fixed in [`0b3eeb2`](https://github.com/Bissbert/POSIX-hardening/commit/0b3eeb2) | Dependency checks never block and never match, `--script` always reports "not found", the summary always counts zero |
| [BUG-10](#bug-10) | `orchestrator.sh` | Low | Rejected on review | `00-ssh-verification.sh` is absent from `SCRIPT_ORDER` |
| [BUG-11](#bug-11) | `quick-start.sh` | Low | Fixed in [`52d6e09`](https://github.com/Bissbert/POSIX-hardening/commit/52d6e09) | Takes no arguments; `--help` starts the interactive installer |
| [BUG-12](#bug-12) | `README.md`, `docs/README.md`, `lib/common.sh:10` | Low | Fixed in [`40a0a2c`](https://github.com/Bissbert/POSIX-hardening/commit/40a0a2c) | Broken links, disagreeing script counts, disagreeing version |
| [BUG-13](#bug-13) | `lib/common.sh:314`, all 21 scripts | High | Fixed in [`41b9617`](https://github.com/Bissbert/POSIX-hardening/commit/41b9617) | A dry run writes a completion marker, so the real run is skipped |
| [BUG-14](#bug-14) | `config/defaults.conf.template:38` | High | Open, needs a decision | The config file overrides the environment, so `DRY_RUN=1` does nothing |
| [BUG-15](#bug-15) | `orchestrator.sh:165`, `lib/common.sh:56` | Blocking | Fixed in [`fe8d65e`](https://github.com/Bissbert/POSIX-hardening/commit/fe8d65e) | `--priority N` runs nothing and exits 0 |
| [BUG-16](#bug-16) | `orchestrator.sh:141` | High | Fixed in [`aa547e8`](https://github.com/Bissbert/POSIX-hardening/commit/aa547e8) | `FAIL_FAST` skips the rest of one priority level and continues |
| [BUG-17](#bug-17) | `lib/rollback.sh:382-394` | Low | Fixed in [`6921928`](https://github.com/Bissbert/POSIX-hardening/commit/6921928) | The checkpoint API has no callers and its action loop never executes |
| [BUG-18](#bug-18) | `ansible/team_keys/generate_keys.sh:50`, `.gitignore:91` | High | Open, needs a decision | A fresh clone ships public keys nobody holds the private half of, and the Ansible path deploys them |
| [BUG-19](#bug-19) | `lib/ssh_safety.sh:130`, `:229`, `:255` | Medium | Fixed in [`42ef7be`](https://github.com/Bissbert/POSIX-hardening/commit/42ef7be) | The SSH watchdog probes with an unguarded `nc` and logs its rollback as successful either way |
| [BUG-20](#bug-20) | `lib/ssh_safety.sh:126-130`, `config/defaults.conf.template:64` | High | Unresolved | The live-daemon config test passes whenever anything holds port 2222, and the toolkit's own emergency daemon holds it |
| [BUG-21](#bug-21) | `scripts/01-ssh-hardening.sh:108` | Medium | Open, needs a decision | `ENABLE_EMERGENCY_ACCESS` is set only by Ansible, so the manual path's emergency fallback is dead code |
| [BUG-22](#bug-22) | `ansible/playbooks/site.yml:115-163` | Medium | Fixed in [`82b3581`](https://github.com/Bissbert/POSIX-hardening/commit/82b3581) | A second, drifted copy of four playbooks; the `playbooks/` copy of `site.yml` cannot resolve any file it deploys |
| [BUG-23](#bug-23) | `ansible/preflight.yml:203-206` | Medium | Fixed in [`5d377a3`](https://github.com/Bissbert/POSIX-hardening/commit/5d377a3) | The pre-flight check starts `ssh`/`sshd` instead of reporting on them |
| [BUG-24](#bug-24) | `scripts/*.sh` | Critical | Open, needs a decision | 20 of 21 scripts register no undo actions, so their rollbacks have an empty stack |

---

## BUG-1

**Status: Fixed in [`77b3632`](https://github.com/Bissbert/POSIX-hardening/commit/77b3632).**

**Sourcing a library rewrites `SCRIPT_DIR` to the caller's directory, so the
library cannot find its own sibling.** <a id="bug-1"></a>

`lib/rollback.sh` and `lib/ssh_safety.sh` both open with:

```sh
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "${SCRIPT_DIR}/posix_compat.sh"
```

When a file is sourced with `.`, `$0` is still the **calling** script, not the
sourced file. Both libraries are only ever sourced. `SCRIPT_DIR` therefore
becomes the caller's directory and `posix_compat.sh` is looked for there, where
it does not exist — it lives in `lib/`.

Because `lib/common.sh` runs `set -e` and is sourced first, the failed `.`
terminates the whole process.

This is not a niche path. It affects `orchestrator.sh`, every script in
`scripts/`, and therefore every command in the README's quick start.

**Verified.** Measured in a container, repository unmodified:

```text
scripts/01-ssh-hardening.sh        exit=2   scripts/01-ssh-hardening.sh: 9: .: cannot open /opt/posix-hardening/scripts/posix_compat.sh: No such file
scripts/03-kernel-params.sh        exit=2   scripts/03-kernel-params.sh: 9: .: cannot open /opt/posix-hardening/scripts/posix_compat.sh: No such file
scripts/05-file-permissions.sh     exit=2   scripts/05-file-permissions.sh: 9: .: cannot open /opt/posix-hardening/scripts/posix_compat.sh: No such file
orchestrator.sh --status           exit=2   orchestrator.sh: 9: .: cannot open /opt/posix-hardening/posix_compat.sh: No such file
orchestrator.sh --dry-run --all    exit=2   orchestrator.sh: 9: .: cannot open /opt/posix-hardening/posix_compat.sh: No such file
```

`dash` blames the outer script; `bash` names the library, which is the clearer
diagnosis:

```text
scripts/01-ssh-hardening.sh        exit=1   /opt/posix-hardening/lib/ssh_safety.sh: line 9: /opt/posix-hardening/scripts/posix_compat.sh: No such file or directory
orchestrator.sh --status           exit=1   /opt/posix-hardening/lib/rollback.sh: line 9: /opt/posix-hardening/posix_compat.sh: No such file or directory
```

### Reproduction

```sh
sh tools/capture-hardening-run.sh
cat media/captures/pristine.txt
```

### Fix proposed at the time

Every caller already sets `LIB_DIR` before sourcing, so the libraries can use
it and fall back to the current behaviour when it is unset.

```diff
--- a/lib/rollback.sh
+++ b/lib/rollback.sh
@@ -5,8 +5,7 @@
 
 # Note: common.sh should be sourced before this file
 # Source POSIX compatibility layer
-SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
-. "${SCRIPT_DIR}/posix_compat.sh"
+. "${LIB_DIR:-$(cd "$(dirname "$0")" && pwd)}/posix_compat.sh"
 
 # Rollback configuration
 readonly ROLLBACK_STACK="$STATE_DIR/rollback_stack"
```

```diff
--- a/lib/ssh_safety.sh
+++ b/lib/ssh_safety.sh
@@ -5,8 +5,7 @@
 
 # Note: common.sh should be sourced before this file
 # Source POSIX compatibility layer
-SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
-. "${SCRIPT_DIR}/posix_compat.sh"
+. "${LIB_DIR:-$(cd "$(dirname "$0")" && pwd)}/posix_compat.sh"
 
 # SSH-specific configuration
 readonly SSHD_CONFIG="${SSHD_CONFIG:-/etc/ssh/sshd_config}"
```

A maintainer may prefer to drop the assignment entirely and require `LIB_DIR`,
since the fallback is exactly the broken behaviour. The form above was chosen
only because it cannot regress a caller that does not set `LIB_DIR`.

**Inferred, not verified:** that the same fix is sufficient for every caller.
Only the entry points listed above were run.

---

## BUG-2

**Status: Fixed in [`a25ce32`](https://github.com/Bissbert/POSIX-hardening/commit/a25ce32).**

**`emergency-rollback.sh` exports two variables that `lib/common.sh` has
already made read-only.** <a id="bug-2"></a>

`emergency-rollback.sh:9-15`:

```sh
# Source only essential functions
. "$LIB_DIR/common.sh"
. "$LIB_DIR/backup.sh"

# Force safety off for emergency
export SAFETY_MODE=0
export DRY_RUN=0
```

`lib/common.sh` declares both `SAFETY_MODE` and `DRY_RUN` `readonly`. Assigning
to a read-only variable is an error, and `set -e` is in force, so the script
dies on line 14 — before it has defined a single recovery function.

The intent in the comment is right: the emergency tool should run with safety
off. The two statements are simply on the wrong side of the `.` lines.

**Verified.**

```text
emergency-rollback.sh --help       exit=2   emergency-rollback.sh: 14: export: SAFETY_MODE: is read only
emergency-rollback.sh --help       exit=1   emergency-rollback.sh: line 14: SAFETY_MODE: readonly variable   (bash)
```

**Reproduction:** `sh tools/capture-hardening-run.sh`, then read
`media/captures/pristine.txt`.

### Fix proposed at the time

```diff
--- a/emergency-rollback.sh
+++ b/emergency-rollback.sh
@@ -6,14 +6,14 @@
 SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
 LIB_DIR="$SCRIPT_DIR/lib"
 
+# Force safety off for emergency
+export SAFETY_MODE=0
+export DRY_RUN=0
+
 # Source only essential functions
 . "$LIB_DIR/common.sh"
 . "$LIB_DIR/backup.sh"
 
-# Force safety off for emergency
-export SAFETY_MODE=0
-export DRY_RUN=0
-
 # ============================================================================
 # Emergency Recovery Functions
 # ============================================================================
```

`lib/common.sh` reads `SAFETY_MODE="${SAFETY_MODE:-1}"` before marking it
read-only, so exporting first produces the intended value.

---

## BUG-3

**Status: Fixed in [`50f241d`](https://github.com/Bissbert/POSIX-hardening/commit/50f241d).**

**`log INFO` writes to stdout, so every `$(safe_backup_file …)` captures a log
line as well as the path.** <a id="bug-3"></a>

This is the most consequential defect found. It is what makes rollback — the
toolkit's central safety claim — not work.

`lib/common.sh:64-74` sends every level except `ERROR` to stdout:

```sh
    # Log to stdout with colors
    case "$level" in
        ERROR)
            printf "${RED}[ERROR]${RESET} %s\n" "$*" >&2
            ;;
        WARN)
            printf "${YELLOW}[WARN]${RESET} %s\n" "$*"
            ;;
        INFO)
            printf "${GREEN}[INFO]${RESET} %s\n" "$*"
            ;;
```

`lib/common.sh:220-223` then logs and echoes on the same stream:

```sh
    if [ -f "$backup_path" ]; then
        log "INFO" "Backed up $source_file to $backup_path"
        echo "$backup_path"
        return 0
```

`lib/backup.sh:60-62` has the identical shape in `backup_file`.

A caller writing `BK=$(safe_backup_file /etc/foo)` gets **two lines**: the log
message first, the path second.

`lib/ssh_safety.sh:95-96` has the same shape with a `DEBUG` log, and `DEBUG`
only reaches stdout when `VERBOSE=1`. So `create_ssh_test_config` is correct at
the default verbosity and wrong the moment an operator turns logging up —
which then breaks `test_ssh_config`, the pre-flight check that is supposed to
prove a new `sshd_config` starts before it is installed.

`tools/capture-stdout-pollution.sh` measures all three functions at both
verbosities
([`media/captures/stdout-pollution.txt`](../media/captures/stdout-pollution.txt)):

```text
=== VERBOSE=0
  safe_backup_file           lines=2  names an existing file: NO
  backup_file                lines=2  names an existing file: NO
  create_ssh_test_config     lines=1  names an existing file: YES

=== VERBOSE=1
  safe_backup_file           lines=2  names an existing file: NO
  backup_file                lines=2  names an existing file: NO
  create_ssh_test_config     lines=2  names an existing file: NO
```

**Verified**, including the `VERBOSE` dependency.

### What that breaks

`register_file_rollback` stores `"${_backup_file}:${_original_file}"` as one
stack entry, so the two-line value writes two physical lines into
`$ROLLBACK_STACK`. `rollback_transaction` reads the stack in reverse with
`while IFS='|' read -r action_type action_data`, so each physical line becomes
its own action: the second line is an action type nobody recognises, and the
first is a `FILE_RESTORE` whose backup path is a log message.

The same value is what `update_ssh_config_safe` hands to its 60-second lockout
watchdog, which does `cp "$_backup_file" "$SSHD_CONFIG"`.

**Verified, three separate ways.**

1. The captured value itself (`media/captures/rollback-demo.log`):

   ```text
   == what safe_backup_file actually returns ==
        1  [INFO] Backed up /etc/demo.conf to /var/backups/hardening/demo.conf.20260921-195638.bak
        2  /var/backups/hardening/demo.conf.20260921-195638.bak
   lines captured: 2
   names an existing file: NO
   ```

2. A full transaction, same capture — the file is not restored:

   ```text
   == rollback stack contents ==
        1  FILE_RESTORE|[INFO] Backed up /etc/demo.conf to /var/backups/hardening/demo.conf.20260921-195638.bak
        2  /var/backups/hardening/demo.conf.20260921-195638.bak:/etc/demo.conf

   == rollback ==
   [WARN] Rolling back transaction: 20260921-195638-146-demo (reason: demo_failed)
   [ERROR] Unknown rollback action type: /var/backups/hardening/demo.conf.20260921-195638.bak:/etc/demo.conf
   [ERROR] Backup file not found: [INFO] Backed up /etc/demo.conf to /var/backups/hardening/demo.conf.20260921-195638.bak
   [INFO] Rollback completed

   == after rollback ==
   HARDENED - this must not survive the rollback

   RESULT: file was NOT restored - the hardened content survived
   ```

3. The real SSH lockout watchdog, fired for real by killing `sshd` one second
   after the script reloads it (`media/captures/ssh-watchdog.log`):

   ```text
   [INFO] SSH config backed up to: [INFO] Backed up /etc/ssh/sshd_config to /var/backups/hardening/sshd_config.20260921-195655.bak
   [INFO] Setting up automatic rollback (15s timeout)
   [INFO] Reloading SSH daemon
   [ERROR] SSH not responding after reload
   [ERROR] SSH not responding - executing rollback
   cp: cannot stat '[INFO] Backed up /etc/ssh/sshd_config to /var/backups/hardening/sshd_config.20260921-195655.bak'$'\n''/var/backups/hardening/sshd_config.20260921-195655.bak': No such file or directory

   sshd_config sha256 before : f7fdf0268371acf5d7277b652179c23ef53ca60d95e934451517f20113463e8e
   sshd_config sha256 after  : 332bb2c5365f29af64a7f215fd700f369964a473147c739750799ab72c7329d5
   RESULT: sshd_config was NOT restored
   sshd back up: no
   ```

   The timeout was lowered from 60s to 15s through the supported
   `SSH_ROLLBACK_TIMEOUT` setting so the capture finishes quickly. Nothing else
   about the code path was altered.

A fourth instance appears without any demo harness at all: in
`media/captures/03-kernel-params.log`, `backup_file`'s stray path is visible on
its own line, and after `[INFO] Rollback completed` the hardening block is
still in `/etc/sysctl.conf`.

### Reproduction

```sh
sh tools/capture-rollback-demo.sh    # the transaction path
sh tools/capture-ssh-watchdog.sh     # the SSH lockout watchdog
```

### Fix proposed at the time

Send diagnostics to stderr and leave stdout for values. This is the smallest
change that fixes all four observed symptoms at once:

```diff
--- a/lib/common.sh
+++ b/lib/common.sh
@@ -61,18 +61,18 @@
     # Log to file
     echo "[$timestamp] [$level] $*" >> "$LOG_FILE"
 
-    # Log to stdout with colors
+    # Log to stderr with colors, so command substitution stays clean
     case "$level" in
         ERROR)
             printf "${RED}[ERROR]${RESET} %s\n" "$*" >&2
             ;;
         WARN)
-            printf "${YELLOW}[WARN]${RESET} %s\n" "$*"
+            printf "${YELLOW}[WARN]${RESET} %s\n" "$*" >&2
             ;;
         INFO)
-            printf "${GREEN}[INFO]${RESET} %s\n" "$*"
+            printf "${GREEN}[INFO]${RESET} %s\n" "$*" >&2
             ;;
         DEBUG)
             if [ "$VERBOSE" = "1" ]; then
-                printf "${BLUE}[DEBUG]${RESET} %s\n" "$*"
+                printf "${BLUE}[DEBUG]${RESET} %s\n" "$*" >&2
             fi
             ;;
```

This is a behaviour change with a visible consequence — anything that pipes a
script's stdout to a file stops collecting the log lines — so it is a
maintainer's decision, not a documentation pass's.

A narrower alternative, if moving the whole logger is unwelcome, is to redirect
only at the two sites that must return a value:

```diff
--- a/lib/common.sh
+++ b/lib/common.sh
@@ -218,7 +218,7 @@
     cp -p "$source_file" "$backup_path"
 
     if [ -f "$backup_path" ]; then
-        log "INFO" "Backed up $source_file to $backup_path"
+        log "INFO" "Backed up $source_file to $backup_path" >&2
         echo "$backup_path"
         return 0
```

```diff
--- a/lib/backup.sh
+++ b/lib/backup.sh
@@ -57,7 +57,7 @@
         ls -la "$_source_file" > "${_backup_path}.meta"
         sha256sum "$_source_file" 2>/dev/null | cut -d' ' -f1 > "${_backup_path}.sha256"
 
-        log "INFO" "Backed up: $_source_file -> $_backup_path"
+        log "INFO" "Backed up: $_source_file -> $_backup_path" >&2
         echo "$_backup_path"
         return 0
```

**Inferred, not verified:** that these are the only two value-returning
functions that call `log`. They are the only two reached by the captures above;
the rest of `lib/` was not audited function by function for this pattern.

Whichever fix is chosen, a regression test belongs with it — asserting that
`safe_backup_file` returns exactly one line that names an existing file.

---

## BUG-4

**Status: Open, needs a decision.** Deferred by the fix pass: whether an omitted `ROLLBACK_ENABLED` should mean rollback on or off is a deployment-policy choice.

**`ROLLBACK_ENABLED` has no default, so a run without `config/defaults.conf`
silently has automatic rollback switched off.** <a id="bug-4"></a>

`lib/rollback.sh:18`:

```sh
ROLLBACK_ENABLED="${ROLLBACK_ENABLED}"
```

Every neighbouring setting in the toolkit uses `${NAME:-default}`. This one
does not, and `config/defaults.conf` is the only thing that sets it. That file
is **not in the repository**: only `config/defaults.conf.template` is, and
nothing creates the real file except `quick-start.sh`.

The exit trap gates on it:

```sh
if [ $_exit_code -ne 0 ] && [ "$ROLLBACK_ENABLED" = "1" ]; then
```

so with the variable empty a failing script leaves its half-applied changes in
place and says nothing at all.

**Verified.** Same script, same container, `config/defaults.conf` removed. The
script still fails, but the two rollback lines that appear otherwise are gone:

```text
==> Applying kernel security parameters
[INFO] Applying kernel security parameters
[INFO] Backed up: /etc/sysctl.conf -> /var/backups/hardening/sysctl.conf.20260921-195934.bak
/var/backups/hardening/sysctl.conf.20260921-195934.bak
```

No `[ERROR] Transaction failed with exit code 1`, no `[WARN] Rolling back`.

### Reproduction

```sh
# in a throwaway container with the repository at /opt/posix-hardening
rm -f config/defaults.conf
sh scripts/03-kernel-params.sh; echo "exit=$?"
```

### Fix that was not applied

```diff
--- a/lib/rollback.sh
+++ b/lib/rollback.sh
@@ -15,7 +15,7 @@
 readonly TRANSACTION_ID_FILE="$STATE_DIR/current_transaction"
 readonly ROLLBACK_LOG="$LOG_DIR/rollback.log"
 
-ROLLBACK_ENABLED="${ROLLBACK_ENABLED}"
+ROLLBACK_ENABLED="${ROLLBACK_ENABLED:-1}"
```

Defaulting to `1` matches `config/defaults.conf.template`, which ships
`ROLLBACK_ENABLED=1`, and makes the safe behaviour the one you get by doing
nothing.

---

## BUG-5

**Status: Fixed in [`7726958`](https://github.com/Bissbert/POSIX-hardening/commit/7726958).**

**`rollback_transaction` returns 0 and logs "Rollback completed" even when
every action in it failed.** <a id="bug-5"></a>

`execute_rollback_action` logs an error and carries on; it does not return a
distinct status and nothing inspects one. `lib/rollback.sh:102-104` closes
unconditionally:

```sh
    log "INFO" "Rollback completed"
    unset _reason
    return 0
```

Worse, the loop runs in a pipeline (`posix_reverse "$_temp_stack" | while …`),
so in a POSIX shell it executes in a subshell and could not propagate a status
even if one were set.

The practical effect is that the operator's last line of output is
`[INFO] Rollback completed` in exactly the case where nothing was rolled back.
Both captures above end that way.

**Verified** as a consequence of the BUG-3 captures: in both, every action
failed and the function still reported completion and exited 0.

### Fix proposed at the time

```diff
--- a/lib/rollback.sh
+++ b/lib/rollback.sh
@@ -83,10 +83,15 @@
     if [ -f "$ROLLBACK_STACK" ] && [ -s "$ROLLBACK_STACK" ]; then
         _temp_stack="${ROLLBACK_STACK}.processing"
         mv "$ROLLBACK_STACK" "$_temp_stack"
+        _failed_file="${ROLLBACK_STACK}.failed"
+        : > "$_failed_file"
 
         # Read stack in reverse order
         posix_reverse "$_temp_stack" | while IFS='|' read -r action_type action_data; do
-            execute_rollback_action "$action_type" "$action_data"
+            execute_rollback_action "$action_type" "$action_data" ||
+                echo "$action_type" >> "$_failed_file"
         done
 
         rm -f "$_temp_stack"
```

with `execute_rollback_action` returning non-zero on its error branches, and
the tail of `rollback_transaction` reading `_failed_file` to decide between
`Rollback completed` and a loud failure. A file is used rather than a variable
because the `while` loop is in a subshell.

This sketch has **not** been run. It is the shape of a fix, not a tested patch.

---

## BUG-6

**Status: Fixed in [`4b7a0b4`](https://github.com/Bissbert/POSIX-hardening/commit/4b7a0b4).**

**One unsupported sysctl key aborts `03-kernel-params.sh`, and the output that
would say which key is discarded.** <a id="bug-6"></a>

`scripts/03-kernel-params.sh:121` is the last statement of
`apply_kernel_hardening`:

```sh
    sysctl -p /etc/sysctl.conf >/dev/null 2>&1
```

`sysctl -p` exits non-zero if **any** key in the file fails, and the script runs
under `set -e`. Both streams are discarded, so the operator sees the script die
with no indication of which of the 65 keys was rejected.

**Verified** in the container. `net.ipv4.tcp_congestion_control` is not
settable there, so the whole script fails:

```text
==> Applying kernel security parameters
[INFO] Applying kernel security parameters
[INFO] Backed up: /etc/sysctl.conf -> /var/backups/hardening/sysctl.conf.20260921-195845.bak
/var/backups/hardening/sysctl.conf.20260921-195845.bak
[ERROR] Transaction failed with exit code 1 - initiating rollback
[WARN] Rolling back transaction: 20260921-195845-1186-kernel_params (reason: exit_code_1)
[INFO] Rollback completed
```

The key was identified separately, by running the same file with output kept:

```text
sysctl: setting key "net.ipv4.tcp_congestion_control": No such file or directory
sysctl -p exit: 1
```

A container is a restricted environment and this specific key may well apply on
a real host. The defect is not that the key fails — it is that a single
unsupported key is fatal and unidentifiable.

**Reproduction:** `sh tools/capture-hardening-run.sh`, then read
`media/captures/03-kernel-params.log` and the last lines of
`media/captures/effects.txt`.

### Fix proposed at the time

```diff
--- a/scripts/03-kernel-params.sh
+++ b/scripts/03-kernel-params.sh
@@ -118,7 +118,10 @@
     # Apply settings
-    sysctl -p /etc/sysctl.conf >/dev/null 2>&1
+    if ! sysctl -p /etc/sysctl.conf 2>&1 >/dev/null | while read -r line; do
+        log "WARN" "sysctl: $line"
+    done; then
+        log "WARN" "some kernel parameters were not applied; see above"
+    fi
 
     show_success "Kernel parameters hardened"
```

Not run. Whether an unsupported key should be a warning or an error is a policy
decision for the maintainer — a hardening tool has a reasonable argument for
either. What is not reasonable is discarding the message.

---

## BUG-7

**Status: Open, needs a decision.** Deferred by the fix pass: fixing it means defining the precedence of config file, environment and CLI flags, together with BUG-8 and BUG-14.

**`orchestrator.sh` sources its libraries before its configuration, so a
`config/defaults.conf` makes it impossible to start.** <a id="bug-7"></a>

`orchestrator.sh:10-17`:

```sh
# Source libraries
. "$LIB_DIR/common.sh"
. "$LIB_DIR/backup.sh"
. "$LIB_DIR/rollback.sh"

# Load configuration
CONFIG_FILE="$SCRIPT_DIR/config/defaults.conf"
[ -f "$CONFIG_FILE" ] && . "$CONFIG_FILE"
```

`lib/common.sh` marks `BACKUP_DIR`, `LOG_DIR`, `STATE_DIR`, `TOOLKIT_PATH`,
`SAFETY_MODE` and `DRY_RUN` read-only. `config/defaults.conf` assigns all of
them. Sourcing the config after the libraries is therefore a guaranteed error,
and `set -e` makes it fatal on the first one.

Every script in `scripts/` gets this right, with the reason in a comment:

```sh
# Load configuration first (before libraries set readonly variables)
[ -f "$CONFIG_FILE" ] && . "$CONFIG_FILE"

# Source libraries
. "$LIB_DIR/common.sh"
```

The orchestrator has the same two blocks in the opposite order.

The practical consequence is a catch-22. `quick-start.sh` creates
`config/defaults.conf`; the README's recommended first step is `quick-start.sh`;
and once that file exists, `orchestrator.sh` — the toolkit's main entry point —
cannot run at all.

**Verified**, with the BUG-1 workaround applied so the script gets that far:

```text
=== 1. with config/defaults.conf present, as quick-start.sh creates it
orchestrator.sh: 20: /opt/posix-hardening/config/defaults.conf: BACKUP_DIR: is read only

=== 2. same command with config/defaults.conf removed
[ ] P3 - 19-log-retention.sh
[ ] P4 - 20-integrity-baseline.sh
=====================================
[INFO] Script completed successfully
```

Note the second consequence: the only way to run the orchestrator today is
without a config file, which is exactly the condition that silently disables
automatic rollback ([BUG-4](#bug-4)).

**Reproduction:** `sh tools/capture-orchestrator.sh`, sections 1 and 2.

### Fix that was not applied

```diff
--- a/orchestrator.sh
+++ b/orchestrator.sh
@@ -7,14 +7,14 @@
 SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
 LIB_DIR="$SCRIPT_DIR/lib"
 
+# Load configuration first (before libraries set readonly variables)
+CONFIG_FILE="$SCRIPT_DIR/config/defaults.conf"
+[ -f "$CONFIG_FILE" ] && . "$CONFIG_FILE"
+
 # Source libraries
 . "$LIB_DIR/common.sh"
 . "$LIB_DIR/backup.sh"
 . "$LIB_DIR/rollback.sh"
 
-# Load configuration
-CONFIG_FILE="$SCRIPT_DIR/config/defaults.conf"
-[ -f "$CONFIG_FILE" ] && . "$CONFIG_FILE"
-
 # ============================================================================
 # Script Execution Order and Dependencies
```

This matches what every script in `scripts/` already does.

---

## BUG-8

**Status: Open, needs a decision.** Deferred by the fix pass: decided together with BUG-7 and BUG-14.

**`orchestrator.sh --dry-run` exports a read-only variable and dies.**
<a id="bug-8"></a>

`orchestrator.sh:342`, in the argument parser:

```sh
        --dry-run|-n)
            export DRY_RUN=1
            shift
            main "$@"
            ;;
```

By this point `lib/common.sh` has been sourced and has made `DRY_RUN`
read-only. This is the same mistake as [BUG-2](#bug-2), in a different file.
`orchestrator.sh:287` has a second instance in the interactive menu.

`--dry-run` is the option the README recommends for a first look at what the
toolkit would do, so this is the first command a cautious operator runs.

**Verified:**

```text
=== 3. --dry-run
orchestrator.sh: 342: export: DRY_RUN: is read only
[ERROR] Script failed with exit code: 2
```

**Reproduction:** `sh tools/capture-orchestrator.sh`, section 3.

### Fix that was not applied

The variable must be set before `lib/common.sh` is sourced, which means
detecting the flag before the sourcing block rather than in the main parser:

```diff
--- a/orchestrator.sh
+++ b/orchestrator.sh
@@ -7,6 +7,14 @@
 SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
 LIB_DIR="$SCRIPT_DIR/lib"
 
+# DRY_RUN becomes readonly in common.sh, so it has to be decided here.
+for _arg in "$@"; do
+    case "$_arg" in
+        --dry-run|-n) DRY_RUN=1; export DRY_RUN ;;
+    esac
+done
+unset _arg
+
 # Load configuration first (before libraries set readonly variables)
```

with the two `export DRY_RUN=1` lines at `:287` and `:342` removed. Not run —
it depends on the BUG-7 fix being applied too.

Alternatively `lib/common.sh` could stop marking `DRY_RUN` and `SAFETY_MODE`
read-only, which would fix this, BUG-2 and the menu instance together. That is
a wider behaviour change and squarely a maintainer's call.

---

## BUG-9

**Status: Fixed in [`0b3eeb2`](https://github.com/Bissbert/POSIX-hardening/commit/0b3eeb2).**

**Three `while` loops that need to change state run in pipelines, so their
state changes are lost in a subshell — and the dependency check compares the
wrong strings anyway.** <a id="bug-9"></a>

In a POSIX shell, each stage of a pipeline runs in a subshell. Variables
assigned there, and `return` statements executed there, do not reach the
parent. `orchestrator.sh` relies on all three. 9a, 9b and 9c below are that
defect in three places; 9d is a separate string-matching defect in the same
function as 9a, and the two hide each other.

### 9a. Dependency checks never block anything

`orchestrator.sh:50-65`:

```sh
check_script_dependencies() {
    local script="$1"
    local deps="$2"

    [ "$deps" = "none" ] && return 0
    [ "$deps" = "all" ] && return 0  # Special case for final script

    echo "$deps" | tr ',' '\n' | while read -r dep; do
        if ! is_completed "$dep"; then
            log "WARN" "Dependency not met: $dep required for $script"
            return 1
        fi
    done

    return 0
}
```

The `return 1` at `:61` leaves the subshell, not the function. Control reaches
`return 0` at `:64` every time. The function cannot fail.

`SCRIPT_ORDER` exists to stop the firewall being configured before SSH is
hardened, and to stop the integrity baseline being taken before everything else
has run. None of that is enforced.

**Verified.** `02-firewall-setup.sh` declares `01-ssh-hardening.sh` as its
dependency. On a system with no completion markers at all, it ran:

```text
=== 4. --script 02-firewall-setup.sh
    SCRIPT_ORDER declares: 1:02-firewall-setup.sh:01-ssh-hardening.sh
    01-ssh-hardening has NOT run:
    (no completion markers yet)
✓ Completed: 02-firewall-setup.sh
```

### 9b. `--script` always reports "Script not found", including on success

`orchestrator.sh:186-206`:

```sh
    local found=0
    echo "$SCRIPT_ORDER" | while IFS=: read -r priority script deps; do
        if [ "$script" = "$script_name" ]; then
            found=1
            ...
```

`found=1` at `:192` is assigned in the subshell. In the parent `found` is still
`0`, so `:205` always runs:

```sh
    if [ "$found" -eq 0 ]; then
        show_error "Script not found: $script_name"
        return 1
    fi
```

**Verified.** The same capture, two lines further on — the script ran, and was
then declared missing:

```text
✓ Completed: 02-firewall-setup.sh
[INFO] SUCCESS: Completed: 02-firewall-setup.sh
✗ Script not found: 02-firewall-setup.sh
[ERROR] Script not found: 02-firewall-setup.sh
[ERROR] Script failed with exit code: 1
```

Anything driving the orchestrator from a Makefile or a CI job sees exit 1 after
a successful run.

### 9c. The final summary always reports zero

`orchestrator.sh:106-107` initialises `completed` and `failed`; both are
incremented at `:139` and `:141`, inside
`get_scripts_by_priority "$priority" | while …`. The summary at `:150-161`
reads the parent's copies, which never changed, and the return value is derived
from `failed`:

```sh
    echo "Total Scripts: $total_scripts"
    echo "Completed: $completed"
    echo "Failed: $failed"
    ...
    [ "$failed" -eq 0 ] && return 0 || return 1
```

So a full `--all` run reports `Completed: 0`, `Failed: 0` whatever happened,
and always returns success.

**Inferred, not verified.** 9a and 9b were observed directly; 9c was not, because
`--all` cannot currently be reached — `--dry-run --all` dies on
[BUG-8](#bug-8) and a real `--all` was not run against a container that would
be destroyed mid-way. It follows from the same subshell rule as the two
confirmed cases and from reading `:106-161`, but it has not been seen.

### Fix proposed at the time

The general shape is to stop piping into the `while`, using a here-document or
a temporary file so the loop body runs in the current shell:

```diff
--- a/orchestrator.sh
+++ b/orchestrator.sh
@@ -54,13 +54,15 @@
     [ "$deps" = "none" ] && return 0
     [ "$deps" = "all" ] && return 0  # Special case for final script
 
-    echo "$deps" | tr ',' '\n' | while read -r dep; do
+    _unmet=0
+    while read -r dep; do
+        [ -z "$dep" ] && continue
         if ! is_completed "$dep"; then
             log "WARN" "Dependency not met: $dep required for $script"
-            return 1
+            _unmet=1
         fi
-    done
+    done <<EOF
+$(echo "$deps" | tr ',' '\n')
+EOF
 
-    return 0
+    [ "$_unmet" -eq 0 ]
 }
```

and equivalently for `run_single_script` and the `--all` loop. Not run. Each of
the three sites needs its own treatment and `run_script` is called from inside
two of them, so this wants a maintainer's eye and a test rather than a
transcription of the sketch above.

### 9d. Dependency names never match completion markers

`SCRIPT_ORDER` spells dependencies with the `.sh` suffix
(`1:02-firewall-setup.sh:01-ssh-hardening.sh`), and `check_script_dependencies`
passes them to `is_completed` unchanged. But `mark_completed` is called by each
script with its own `SCRIPT_NAME`, which has no suffix
(`SCRIPT_NAME="05-file-permissions"`), and the two other `is_completed` call
sites in `orchestrator.sh` strip it explicitly (`is_completed "${script%.sh}"`
at `:122`, `:172`, `:219`). `check_script_dependencies` is the only caller that
does not.

The comparison in `is_completed` is `grep -q "^$script_name$"`, so
`01-ssh-hardening.sh` never matches the marker `01-ssh-hardening`. No
dependency is ever satisfied.

**Verified.** In a full `--all` run, `01-ssh-hardening.sh` completes and is
marked, and the very next dependency check on it fails
([`media/captures/orchestrator.log`](../media/captures/orchestrator.log),
section 6):

```text
    a dependency reported unmet immediately after it succeeded:
      ✓ Completed: 01-ssh-hardening.sh
      [INFO] SUCCESS: Completed: 01-ssh-hardening.sh
      [WARN] Dependency not met: 01-ssh-hardening.sh required for 02-firewall-setup.sh
    completion markers written (note: no ".sh" suffix):
      00-ssh-verification
      01-ssh-hardening
```

Two defects are cancelling here. 9d means every dependency check would fail;
9a means the failure is discarded. Fixing 9a alone would deadlock the
orchestrator: every script would be skipped for unmet dependencies. They have
to be fixed together, which is the main reason this pass documents rather than
patches them.

**Fix proposed at the time:**

```diff
--- a/orchestrator.sh
+++ b/orchestrator.sh
@@ check_script_dependencies() {
-        if ! is_completed "$dep"; then
+        if ! is_completed "${dep%.sh}"; then
```

---

## BUG-10

**Status: Rejected on review.** `01-ssh-hardening.sh` runs `00` as its
pre-flight step, and an internal step does not have to be independently
schedulable. Nothing was changed.

**`00-ssh-verification.sh` exists but is not in the orchestrator's
`SCRIPT_ORDER`.** <a id="bug-10"></a>

`scripts/` contains 21 numbered scripts, `00` through `20`. `SCRIPT_ORDER` in
`orchestrator.sh` lists 20 of them, starting at `01`.

`00-ssh-verification.sh` is not orphaned — `scripts/01-ssh-hardening.sh` calls
it directly during its pre-flight checks, which is why it appears in the
completion markers after a successful capture:

```text
--- completion markers ---
00-ssh-verification
01-ssh-hardening
05-file-permissions
```

So `orchestrator.sh --all` does run it, indirectly, as long as `01` runs. But
`orchestrator.sh --script 00-ssh-verification.sh` and `--status` do not know
about it, and the discrepancy is the source of the "20 scripts" / "21 scripts"
disagreement in the documentation (BUG-12).

**Verified** by reading `SCRIPT_ORDER` and by the completion markers in
`media/captures/effects.txt`.

**Suggested at the time, not taken:** either add a `SCRIPT_ORDER` entry for it, or
document it as an internal pre-flight step that is deliberately not
independently schedulable. This pass documents the current behaviour and takes
no position on which is right.

---

## BUG-11

**Status: Fixed in [`52d6e09`](https://github.com/Bissbert/POSIX-hardening/commit/52d6e09).**

**`quick-start.sh` parses no arguments.** <a id="bug-11"></a>

There is no `case "$1"` and no `--help` handling anywhere in the file.
`sh quick-start.sh --help` starts the interactive installer, which is a
surprising response to `--help` on a script that modifies system configuration.

**Verified:**

```text
=== quick-start.sh --help full ===
╔══════════════════════════════════════════════════════════════════╗
║     POSIX Shell Server Hardening Toolkit - Quick Start          ║
╚══════════════════════════════════════════════════════════════════╝

Checking prerequisites...
✓ Debian-based system detected
✓ SSH server found
⚠ Configuration file already exists
Overwrite existing configuration? (y/N):
```

With stdin not attached to a terminal, the read fails and the script exits 1.
Interactively it would proceed.

**Fix proposed at the time:** add an argument parser that handles `-h|--help`
before any prompt or system check.

---

## BUG-12

**Status: Fixed in [`40a0a2c`](https://github.com/Bissbert/POSIX-hardening/commit/40a0a2c).**

**Documentation facts that disagree with the repository.** <a id="bug-12"></a>

| Claim | Where | Reality |
|---|---|---|
| "all 21 hardening scripts" | `README.md:9` | Correct: 21 files match `scripts/[0-9][0-9]-*.sh`. Kept here because it disagrees with `docs/`. |
| "22 scripts" | `docs/README.md:13` | 21 |
| "All 20 scripts explained" | `docs/README.md:55` | 21 exist; 20 are in `SCRIPT_ORDER` |
| Link to `docs/user-guide/troubleshooting.md` | `README.md:425` | `docs/user-guide/` is empty; the file does not exist |
| Link to `docs/ANSIBLE_REVIEW_AND_RECOMMENDATIONS.md` | `README.md:426` | Does not exist |
| "100% POSIX Compliant … no bash required" | `README.md:18`, `:469` | True for `lib/` — ShellCheck reports 0 `SC3043` there. Not true overall: 74 uses of the non-POSIX `local`, including 12 in `orchestrator.sh` |
| Version `1.1.0` | `README.md:465`, `VERSION` | `lib/common.sh:10` declares `readonly VERSION="1.0.0"`, and that is the value the scripts print at runtime |

The version disagreement is visible in every capture, which prints
`Starting: 03-kernel-params (v1.0.0)` on a repository whose `VERSION` file says
`1.1.0`.

**Verified.** Counts are from `tools/static-analysis.sh`; links were checked by
listing the paths; the runtime version is from the captures.

**Fixes that were not applied:** the two broken links should be removed or the
documents written; the counts should be reconciled against `scripts/`; and
`lib/common.sh` should read its version from the `VERSION` file, or the two
should be kept in step by a release process. `README.md` and `docs/README.md`
were both rewritten in this pass and no longer carry the wrong numbers, but
`lib/common.sh:10` is source and was left alone.

---

## BUG-13

**Status: Fixed in [`41b9617`](https://github.com/Bissbert/POSIX-hardening/commit/41b9617).**

**A dry run writes a completion marker, so the real run is skipped.**
<a id="bug-13"></a>

Every one of the 21 numbered scripts has the same `main()` shape: the
`DRY_RUN` test guards the work, and `mark_completed` sits *outside* it.
`scripts/05-file-permissions.sh:56-62` is representative:

```sh
    if [ "$DRY_RUN" = "1" ]; then
        log "DRY_RUN" "Would secure file permissions"
    else
        secure_system_files
    fi

    mark_completed "$SCRIPT_NAME"
```

`mark_completed` (`lib/common.sh:314`) appends the script name to
`$STATE_DIR/completed`, and `is_completed` (`lib/common.sh:302`) is what
`orchestrator.sh` consults at lines 122, 172 and 219 to decide whether to run a
script at all. A simulation therefore marks the machine as hardened.

**Reproduction** — `tools/capture-hardening-run.sh`, sections B and C of
[`media/captures/dry-run.txt`](../media/captures/dry-run.txt):

```text
=== B. DRY_RUN=1 with config/defaults.conf removed
⚠ Running in DRY-RUN mode - no changes will be made
[WARN] Running in DRY-RUN mode - no changes will be made
[DRY-RUN] Would secure file permissions
[INFO] Marked as completed: 05-file-permissions
    completion markers after the DRY RUN:
      05-file-permissions
```

`orchestrator.sh --status` then reports `[✓] P2 - 05-file-permissions.sh` on a
host where nothing was changed.

**Verified** for `05-file-permissions.sh`, including the resulting `--status`
line. **Inferred by reading** for the other 20 scripts: in each of them the
single `mark_completed` call is the statement after the `fi` that closes the
`DRY_RUN` branch, so the same sequence applies.

**Fix proposed at the time:**

```diff
--- a/scripts/05-file-permissions.sh
+++ b/scripts/05-file-permissions.sh
@@
     if [ "$DRY_RUN" = "1" ]; then
         log "DRY_RUN" "Would secure file permissions"
+        commit_transaction
+        show_success "File permissions hardening simulated"
+        exit 0
     else
         secure_system_files
     fi
```

or, less repetitively, a guard inside `mark_completed` itself:

```diff
--- a/lib/common.sh
+++ b/lib/common.sh
@@ mark_completed() {
     script_name="$1"
     completion_file="$STATE_DIR/completed"
 
+    [ "$DRY_RUN" = "1" ] && return 0
+
     if ! is_completed "$script_name"; then
```

The second form changes all 21 scripts at once and is the one this pass would
have chosen.

---

## BUG-14

**Status: Open, needs a decision.** Deferred by the fix pass: decided together with BUG-7 and BUG-8: do CLI and environment override the file, and for which settings.

**`config/defaults.conf` silently overrides the environment.**
<a id="bug-14"></a>

The config file assigns unconditionally:

```sh
config/defaults.conf.template:38:DRY_RUN=0   # 0=apply changes, 1=simulation only
```

and every numbered script sources it *before* `lib/common.sh`, deliberately:

```sh
# Load configuration first (before libraries set readonly variables)
[ -f "$CONFIG_FILE" ] && . "$CONFIG_FILE"
. "$LIB_DIR/common.sh"
```

`lib/common.sh:16` then reads `readonly DRY_RUN="${DRY_RUN:-0}"`, which honours
whatever the config file just set. So `DRY_RUN=1 sh scripts/05-…` is a no-op
whenever a config file exists — which is exactly the state `quick-start.sh`
leaves the toolkit in. The same applies to every other tunable the template
assigns, including `SAFETY_MODE`, `ROLLBACK_ENABLED` and `FAIL_FAST`.

This directly contradicts the template's own advice at line 195:

```text
# 3. Test in a sandbox environment first (use DRY_RUN=1)
```

**Reproduction** — `tools/capture-hardening-run.sh`, section A of
[`media/captures/dry-run.txt`](../media/captures/dry-run.txt):

```text
=== A. DRY_RUN=1 with config/defaults.conf present
DRY_RUN=0                    # 0=apply changes, 1=simulation only
    lines containing DRY-RUN: 0
```

Zero `DRY-RUN` lines: the run applied changes. With the file moved aside, the
same command prints `[DRY-RUN] Would secure file permissions`.

**Verified.**

**Fix that was not applied:** make the config file's assignments defaults, so
the environment wins:

```diff
--- a/config/defaults.conf.template
+++ b/config/defaults.conf.template
@@
-DRY_RUN=0                    # 0=apply changes, 1=simulation only
+DRY_RUN="${DRY_RUN:-0}"      # 0=apply changes, 1=simulation only
```

applied to each tunable the file sets. This is a one-line-per-setting change
with no behavioural effect when the variable is not already exported.

---

## BUG-15

**Status: Fixed in [`fe8d65e`](https://github.com/Bissbert/POSIX-hardening/commit/fe8d65e).**

**`orchestrator.sh --priority N` runs nothing, and exits 0.**
<a id="bug-15"></a>

`log()` at `lib/common.sh:56` assigns `level="$1"` without `local`.
`run_priority_level()` at `orchestrator.sh:163-165` keeps its argument in a
variable of the same name:

```sh
run_priority_level() {
    local level="$1"

    show_progress "Running Priority $level scripts only"

    get_scripts_by_priority "$level" | while IFS=: read -r script deps; do
```

`local` in `dash`, `bash` and `busybox sh` is dynamically scoped: a function
called from `run_priority_level` that assigns `level` writes to
`run_priority_level`'s local. `show_progress` calls `log "INFO" …`, so by the
time `get_scripts_by_priority "$level"` is evaluated, `level` is the string
`INFO`. No entry in `SCRIPT_ORDER` has priority `INFO`, the pipeline emits
nothing, the loop body never runs, and the orchestrator reports success.

**Reproduction** — `tools/capture-orchestrator.sh`, section 5 of
[`media/captures/orchestrator.log`](../media/captures/orchestrator.log):

```text
=== 5. --priority 2
    priority-2 entries in SCRIPT_ORDER:
      2:03-kernel-params.sh:none
      2:04-network-stack.sh:02-firewall-setup.sh,03-kernel-params.sh
      2:05-file-permissions.sh:none
      2:06-process-limits.sh:03-kernel-params.sh
      2:10-sudo-restrictions.sh:09-account-lockdown.sh
      2:14-sysctl-hardening.sh:03-kernel-params.sh,04-network-stack.sh
    no completion markers exist, so all of them are due to run:

==> Running Priority 2 scripts only
[INFO] Running Priority 2 scripts only
[INFO] Script completed successfully
exit=0
    the argument get_scripts_by_priority was actually called with,
    from sh -x:
      get_scripts_by_priority INFO
```

**Verified**, including the `sh -x` line that names the clobbered value.

**Fix proposed at the time:** rename the caller's variable, since the library
function is the one with the wider blast radius but the smaller diff is here.

```diff
--- a/orchestrator.sh
+++ b/orchestrator.sh
@@ run_priority_level() {
-    local level="$1"
+    local _level="$1"
 
-    show_progress "Running Priority $level scripts only"
+    show_progress "Running Priority $_level scripts only"
 
-    get_scripts_by_priority "$level" | while IFS=: read -r script deps; do
+    get_scripts_by_priority "$_level" | while IFS=: read -r script deps; do
```

The library side deserves the same treatment — `log()` should use `_level` and
`_timestamp`, and the other unprefixed globals listed below should be prefixed
too — because the collision class is wider than this one instance.
`lib/common.sh` assigns these names from inside functions without `local`:
`level`, `timestamp`, `message`, `script_name`, `key`, `value`, `state_file`,
`completion_file`, `source_file`, `backup_path`, `backup_name`, `target_file`,
`service_name`, `exit_code`, `missing`, `available`, `current_hash`,
`original_hash`, `file`. Any caller that keeps a `local` of the same name
across a library call is exposed. `orchestrator.sh:186` (`local script_name`)
is the second instance in this repository; it happens not to misbehave, because
nothing clobbers `script_name` between the assignment and its last use.

---

## BUG-16

**Status: Fixed in [`aa547e8`](https://github.com/Bissbert/POSIX-hardening/commit/aa547e8).**

**`FAIL_FAST` does not stop the run: it skips the rest of one priority level
and carries on.** <a id="bug-16"></a>

`lib/common.sh:18` makes fail-fast the default (`readonly
FAIL_FAST="${FAIL_FAST:-1}"`), and `orchestrator.sh:134-147` implements it:

```sh
        get_scripts_by_priority "$priority" | while IFS=: read -r script deps; do
            ...
            if run_script "$script"; then
                completed=$((completed + 1))
            else
                failed=$((failed + 1))

                if [ "$FAIL_FAST" = "1" ]; then
                    show_error "Stopping execution due to failure"
                    break 2
                fi
            fi
```

The `while` loop is the right-hand side of a pipeline, so it runs in a
subshell. The `for priority in 1 2 3 4` loop it is trying to break out of is in
the *parent* shell and is not visible from there. `break 2` therefore leaves
the one loop it can see, the subshell exits, and the `for` loop moves on to the
next priority level as if nothing had happened. The operator sees
`Stopping execution due to failure` and the run does not stop.

The practical effect is worse than either "stop" or "continue" would be: the
remaining scripts *at the failing priority level* are silently skipped, while
every later level runs. Priority levels exist to express ordering, so the
scripts that get dropped are the ones that were meant to run before the ones
that do.

**Reproduction** — `tools/capture-orchestrator.sh`, section 6 of
[`media/captures/orchestrator.log`](../media/captures/orchestrator.log). A full
`--all` run in a fresh container, with no completion markers:

```text
    the moment FAIL_FAST is supposed to stop the run:
      ✗ Stopping execution due to failure
      [ERROR] Stopping execution due to failure

      ==> Processing Priority 3 scripts
      --
      ✗ Stopping execution due to failure
      [ERROR] Stopping execution due to failure

      ==> Processing Priority 4 scripts
    scripts in SCRIPT_ORDER that were never executed:
      04-network-stack.sh
      05-file-permissions.sh
      06-process-limits.sh
      10-sudo-restrictions.sh
      14-sysctl-hardening.sh
      16-mount-options.sh
      19-log-retention.sh
    declared / executed:
      20 / 13
    final summary:
      Total Scripts: 20
      Completed: 0
      Failed: 0
```

Seven of the twenty declared scripts never ran. `03-kernel-params.sh` failed
(BUG-6) and took the rest of priority 2 with it; `15-cron-restrictions.sh`
failed and took the rest of priority 3. The orchestrator exited 0 and reported
zero failures (BUG-9c).

**Verified.**

**Fix proposed at the time:** the subshell has to go, which is the same
underlying change BUG-5 and BUG-9 need. Feeding the loop from a here-document
instead of a pipeline keeps it in the current shell, and then `break 2` means
what it says:

```diff
--- a/orchestrator.sh
+++ b/orchestrator.sh
@@ run_all_scripts() {
     for priority in 1 2 3 4; do
         show_progress "Processing Priority $priority scripts"
 
-        get_scripts_by_priority "$priority" | while IFS=: read -r script deps; do
+        while IFS=: read -r script deps; do
             [ -z "$script" ] && continue
@@
             # Brief pause between scripts
             sleep 2
-        done
+        done <<EOF
+$(get_scripts_by_priority "$priority")
+EOF
     done
```

The same rewrite also makes the `completed` and `failed` counters survive, so
it fixes BUG-9c at the same time.

---

## BUG-17

**Status: Fixed in [`6921928`](https://github.com/Bissbert/POSIX-hardening/commit/6921928).**

**The checkpoint API is never called, and would not work if it were.**
<a id="bug-17"></a>

`lib/rollback.sh` exports a checkpoint mechanism — `create_checkpoint` at
`:363` and `rollback_to_checkpoint` at `:382` — which lets a script undo part
of a transaction. Nothing in the repository calls either function:

```console
$ grep -rn "rollback_to_checkpoint\|create_checkpoint" . --exclude-dir=.git
lib/rollback.sh:363:create_checkpoint() {
lib/rollback.sh:382:rollback_to_checkpoint() {
lib/rollback.sh:531:#export -f create_checkpoint rollback_to_checkpoint
```

That is a documentation problem in itself, because the feature reads as
available. It is also unusable as written, for two separate reasons.

**The action loop never runs.** `lib/rollback.sh:391-394`:

```sh
        tac "$_temp_actions" 2>/dev/null || tail -r "$_temp_actions" 2>/dev/null | while IFS='|' read -r action_type action_data; do
            execute_rollback_action "$action_type" "$action_data"
        done
```

A pipeline binds tighter than `||`, so this parses as
`tac F || ( tail -r F | while … done )`. On any system with coreutils, `tac`
succeeds, its output goes to standard output, and the `while` loop is never
reached. The checkpoint's actions get *printed* rather than executed. On a
system without `tac` the loop would run — and `tail -r` is a BSD spelling that
is not present on Debian either, so there it would read from an empty pipe.

Neither `tac` nor `tail -r` is POSIX, which is worth noting in a toolkit whose
README advertises POSIX compliance. `lib/posix_compat.sh` already provides
`posix_reverse` for exactly this, and `rollback_transaction` uses it four lines
of code earlier.

**`comm` is given unsorted input.** `:392` uses
`comm -13 "$_checkpoint_file" "$ROLLBACK_STACK"` to find the actions added
since the checkpoint. `comm` requires both inputs to be sorted; the rollback
stack is in chronological order. For a stack that happens to be ascending the
result is right by accident, and for any other order `comm` produces a wrong
set silently.

**Verified:** that the functions have no callers, and that the `||`/pipeline
precedence suppresses the loop. The latter is demonstrated for `dash`, `bash`
and `busybox sh` by `tools/shell-semantics-demo.sh`, section 4 of
[`media/captures/shell-semantics.txt`](../media/captures/shell-semantics.txt):

```text
--- 4. A || B | C parses as A || (B | C), so when A succeeds
---    the loop in C never runs (BUG-17)
B|2
A|1
  (no LOOP SAW line above: tac printed and the loop was skipped)
```

**Inferred by reading:** the `comm` sorting problem. No script creates a
checkpoint, so there was no stack to reproduce it against.

**Fix proposed at the time:**

```diff
--- a/lib/rollback.sh
+++ b/lib/rollback.sh
@@ rollback_to_checkpoint() {
-    comm -13 "$_checkpoint_file" "$ROLLBACK_STACK" > "$_temp_actions" 2>/dev/null
+    # actions added after the checkpoint are the lines the checkpoint copy
+    # does not have, in stack order - not a set difference
+    _n=$(wc -l < "$_checkpoint_file")
+    tail -n "+$((_n + 1))" "$ROLLBACK_STACK" > "$_temp_actions"
 
     # Execute rollback for actions after checkpoint
     if [ -s "$_temp_actions" ]; then
-        tac "$_temp_actions" 2>/dev/null || tail -r "$_temp_actions" 2>/dev/null | while IFS='|' read -r action_type action_data; do
+        posix_reverse "$_temp_actions" | while IFS='|' read -r action_type action_data; do
             execute_rollback_action "$action_type" "$action_data"
         done
```

The `while` loop still runs in a subshell, but nothing after it depends on
state it sets, so that is survivable here — unlike in
[BUG-9](#bug-9) and [BUG-16](#bug-16).

---

## BUG-18

**Status: Open, needs a decision.** Deferred by the fix pass: needs a decision on who owns the shipped keys, how they are rotated and revoked, and whether example keys may be enabled by default.

**A fresh clone ships two public keys whose private halves nobody has, and
the Ansible path deploys them.**
<a id="bug-18"></a>

`ansible/team_keys/generate_keys.sh` is the documented way to create the two
keys the toolkit uses: an automation key that stays on the Ansible controller
and a shared team key that humans carry. `ansible/team_keys/README.md` is
explicit that private keys must never be committed, and `.gitignore:87-95`
implements that — it blocks `*_ed25519` and re-admits `*.pub`.

The public halves are therefore committed, and the users role points at them
by default (`ansible/roles/posix_hardening_users/defaults/main.yml:18-19`):

```yaml
posix_hardening_ansible_key_path: "{{ playbook_dir }}/team_keys/ansible_ed25519.pub"
posix_hardening_team_key_path:    "{{ playbook_dir }}/team_keys/team_shared_ed25519.pub"
```

So a clone arrives with two public keys already in the exact location
`deploy_keys.yml` reads from. The private halves exist only on whichever
machine first ran `generate_keys.sh`.

The regeneration path does not correct this, because `key_exists` at
`ansible/team_keys/generate_keys.sh:50` is satisfied by the public file alone:

```sh
key_exists() {
    local key_name="$1"
    if [ -f "$KEYS_DIR/$key_name" ] || [ -f "$KEYS_DIR/${key_name}.pub" ]; then
        return 0
    fi
    return 1
}
```

`deploy_keys.yml` then `stat`s those same paths, finds them present, skips its
"Warn if keys are missing" task, and installs both keys into
`/root/.ssh/authorized_keys` and into the `authorized_keys` of every name in
`posix_hardening_users_list` — while `scripts/01-ssh-hardening.sh` sets
`PasswordAuthentication no`. The operator running the play holds no matching
private key.

**Reproduction**, `tools/capture-team-keys.sh`, raw output in
[`media/captures/team-keys.txt`](../media/captures/team-keys.txt):

```text
=== 2. the same directory in a fresh clone
    ansible_ed25519.pub
    generate_keys.sh
    install_team_key.sh
    README.md
    team_shared_ed25519.pub

=== 4. generate_keys.sh run in that fresh clone
    [INFO] Generating ansible_ed25519...
    [WARNING] Key ansible_ed25519 already exists, skipping generation
    [INFO] Generating team_shared_ed25519...
    [WARNING] Key team_shared_ed25519 already exists, skipping generation
      (No private keys found)
    exit status: 0

=== 5. private keys present in the clone afterwards
    (nothing listed above means none)
```

The script prints "(No private keys found)" in its own closing summary and
still exits 0, then offers to install the team key on the local machine.

The committed keys, for anyone checking a clone:

| File | Fingerprint |
|---|---|
| `ansible_ed25519.pub` | `SHA256:S7Z7K/80/EdFifFBu7xnq8s5SAY3H2NGnweT4TguV9s` |
| `team_shared_ed25519.pub` | `SHA256:7yHffuV420KbdPbB4PAXodEqG0WY4/GEpm4BOXzPwBQ` |

**Verified:** that both `.pub` files are tracked, that a fresh clone contains
them, that `generate_keys.sh` refuses to generate over them and exits 0, and
that the role defaults resolve to those paths.

**Inferred by reading:** that `deploy_keys.yml` would install them. No Ansible
run against real hosts was performed; the conclusion follows from the `stat`
conditions and the `authorized_key` tasks in that file.

**Fix that was not applied.** Two parts. First, stop treating a lone public
key as proof that a key pair exists:

```diff
--- a/ansible/team_keys/generate_keys.sh
+++ b/ansible/team_keys/generate_keys.sh
@@ key_exists() {
     local key_name="$1"
-    if [ -f "$KEYS_DIR/$key_name" ] || [ -f "$KEYS_DIR/${key_name}.pub" ]; then
+    # only the private half proves this machine owns the pair; a stray .pub
+    # from a clone must not block generation
+    if [ -f "$KEYS_DIR/$key_name" ]; then
         return 0
     fi
     return 1
 }
```

Second, stop shipping the keys at all. The `.pub` files are not needed in the
repository — every consumer of them is generated locally:

```diff
--- a/.gitignore
+++ b/.gitignore
@@
 ansible/team_keys/*.pem
 ansible/team_keys/*.key
-!ansible/team_keys/*.pub
+ansible/team_keys/*.pub
 !ansible/team_keys/README.md
```

with `git rm --cached ansible/team_keys/ansible_ed25519.pub
ansible/team_keys/team_shared_ed25519.pub` to remove the two that are already
tracked. `deploy_keys.yml` already handles their absence: its `stat` check
fails, and it prints the "Generate with: ./generate_keys.sh" warning it was
written for.

Anyone who has already run the Ansible path against a host should check
`/root/.ssh/authorized_keys` for the two fingerprints above and remove them.

---

## BUG-19

**Status: Fixed in [`42ef7be`](https://github.com/Bissbert/POSIX-hardening/commit/42ef7be).**

**The SSH rollback watchdog probes with `nc` and does not check that `nc`
exists.**
<a id="bug-19"></a>

`lib/ssh_safety.sh` decides whether SSH survived a config change by calling
`nc` directly, at `:42`, `:130`, `:229` and `:255`:

```sh
if ! timeout "$SSH_TEST_TIMEOUT" nc -z localhost "$SSH_PORT" 2>/dev/null; then
```

`nc` is not in Debian's base system, nothing in the toolkit installs it, and
`check_requirements` in `lib/common.sh` checks only for
`awk sed grep cp mv mkdir chmod chown cat`. The first of the four call sites
is guarded by `command -v nc` at `:41`; the other three are not. On a host
without `nc`, `nc -z` fails the same way a dead sshd does, and those three
read that failure as "SSH is down":

| Line | Guarded | Function | Effect when `nc` is absent |
|---|---|---|---|
| `:42` | yes, at `:41` | `verify_ssh_connection` | The check is skipped; the function falls through to its `sshd -t` check |
| `:130` | no | `test_ssh_config` | The test daemon on port 2222 is judged dead, so every change is rejected |
| `:229` | no | the watchdog subshell | Fires on every run |
| `:255` | no | the post-reload check | Reports failure after a change that succeeded |

The toolkit already has the right helper: `check_port_listening` in
`lib/common.sh:488` tries `nc`, then `ss`, then `netstat`, each behind a
`command -v` guard, and `scripts/00-ssh-verification.sh` uses it at `:256`
and `:286`. `lib/ssh_safety.sh` does not.

Once [BUG-3](#bug-3) is fixed and the watchdog's `cp` starts working, this
turns from a false alarm into a live regression: a successful SSH hardening
run on an `nc`-less host would be silently reverted 60 seconds later.

A second, smaller defect sits in the same subshell. `lib/ssh_safety.sh:234`
logs the outcome unconditionally:

```sh
            cp "$_backup_file" "$SSHD_CONFIG"
            kill -HUP "$(cat /var/run/sshd.pid 2>/dev/null)" 2>/dev/null || \
                /usr/sbin/sshd
            log "INFO" "SSH configuration rolled back"
```

Neither the `cp` nor the daemon restart is checked. That is why the captured
run in [`media/captures/ssh-watchdog.log`](../media/captures/ssh-watchdog.log)
ends with a `cp: cannot stat` error and a success line — the same pattern as
[BUG-5](#bug-5).

**Verified:** that `lib/ssh_safety.sh` calls `nc` at those four lines with no
`command -v` guard, that `check_port_listening` exists in `lib/common.sh` with
three guarded methods, and that the rollback log line is unconditional. The
captured watchdog run shows the unconditional logging in practice.

**Inferred by reading:** the per-call-site effects in the table above. The
analysis container had `nc` installed, so the `nc`-absent path was not
exercised.

**Fix proposed at the time:**

```diff
--- a/lib/ssh_safety.sh
+++ b/lib/ssh_safety.sh
@@
     (
         sleep "$SSH_ROLLBACK_TIMEOUT"
-        if ! timeout "$SSH_TEST_TIMEOUT" nc -z localhost "$SSH_PORT" 2>/dev/null; then
+        if ! check_port_listening localhost "$SSH_PORT" "$SSH_TEST_TIMEOUT"; then
             log "ERROR" "SSH not responding - executing rollback"
-            cp "$_backup_file" "$SSHD_CONFIG"
-            kill -HUP "$(cat /var/run/sshd.pid 2>/dev/null)" 2>/dev/null || \
-                /usr/sbin/sshd
-            log "INFO" "SSH configuration rolled back"
+            if cp "$_backup_file" "$SSHD_CONFIG"; then
+                kill -HUP "$(cat /var/run/sshd.pid 2>/dev/null)" 2>/dev/null || \
+                    /usr/sbin/sshd
+                log "INFO" "SSH configuration rolled back"
+            else
+                log "ERROR" "SSH rollback FAILED: could not restore $_backup_file"
+            fi
         fi
     ) &
```

The same substitution applies at `:42`, `:130` and `:255`.

---

## BUG-20

**Status: Unresolved.** Confirming it needs an isolated OpenSSH target; the
behaviour below still reproduces in
[`media/captures/emergency-ssh.txt`](../media/captures/emergency-ssh.txt).

**The "boot a real sshd with the new config" check passes whenever anything
is listening on port 2222 — including the toolkit's own emergency daemon.**
<a id="bug-20"></a>

`test_ssh_config` is the strongest safety check in the SSH path: after the
syntax check it starts a real `sshd` on `SSHD_TEST_PORT` with the candidate
configuration and connects to it. `lib/ssh_safety.sh:126-130`:

```sh
        if /usr/sbin/sshd -f "$_test_config_result"; then
            sleep 2

            # Test connection to test instance
            if timeout "$SSH_TEST_TIMEOUT" nc -z localhost "$SSHD_TEST_PORT" 2>/dev/null; then
```

Neither half establishes what it appears to. `sshd` without `-D` forks and the
parent exits 0 before the child's `bind()` result is known, so the `if` is true
whether or not the daemon survives. The `nc -z` that follows then probes the
*port*, not the daemon that was just started, and is answered by whatever holds
it. The `PidFile /var/run/sshd_test.pid` the test config asks for is never
checked.

This is not hypothetical, because the toolkit puts something on that port
itself. Three defaults collide:

| Setting | Default | Where |
|---|---|---|
| `SSHD_TEST_PORT` | 2222 | `lib/ssh_safety.sh:12` |
| `EMERGENCY_SSH_PORT` | 2222 | `config/defaults.conf.template:64` |
| `ssh_test_port` / `emergency_ssh_port` | 2222 / 2222 | `ansible/group_vars/all.yml:60`, `:70` |

`create_emergency_ssh_access` is called from `scripts/00-ssh-verification.sh:214`
and `scripts/01-ssh-hardening.sh:109`. Once it has run, every subsequent
`test_ssh_config` is answered by the emergency daemon — which is running the
*deliberately weakened* emergency config, not the candidate one.

**Reproduction**, `tools/capture-emergency-ssh.sh`, raw output in
[`media/captures/emergency-ssh.txt`](../media/captures/emergency-ssh.txt).
Section 4 runs `test_ssh_config` while the emergency daemon holds 2222:

```text
    listeners before the test:
      LISTEN 0      128          0.0.0.0:2222      0.0.0.0:*    users:(("sshd",pid=166,fd=3))
      LISTEN 0      128             [::]:2222         [::]:*    users:(("sshd",pid=166,fd=4))
    [INFO] Testing SSH configuration: /tmp/candidate
    [INFO] Test SSH daemon is accepting connections
        test_ssh_config returned: 0
    listeners after the test:
      LISTEN 0      128          0.0.0.0:2222      0.0.0.0:*    users:(("sshd",pid=166,fd=3))
      LISTEN 0      128             [::]:2222         [::]:*    users:(("sshd",pid=166,fd=4))
    /var/run/sshd_test.pid:
      ls: cannot access '/var/run/sshd_test.pid': No such file or directory
```

The only listener before the test is the one after it, pid 166, the emergency
daemon. No test daemon ever existed. Section 5 runs the same start by hand so
its exit status is visible:

```text
    the port and pid file the test config asks for:
      Port 2222
      PidFile /var/run/sshd_test.pid
    /usr/sbin/sshd -f exit status: 0
    listeners on 2222 afterwards:
      LISTEN 0      128          0.0.0.0:2222      0.0.0.0:*    users:(("sshd",pid=166,fd=3))
      LISTEN 0      128             [::]:2222         [::]:*    users:(("sshd",pid=166,fd=4))
    /var/run/sshd_test.pid:
      ls: cannot access '/var/run/sshd_test.pid': No such file or directory
```

`sshd -f` returned 0, bound nothing and left nothing behind.

**Verified:** all of the above, in a Debian 12 container with OpenSSH 9.2p1.

**Inferred by reading:** that this weakens the guarantee in practice rather
than only in the lab. A candidate config that parses but cannot serve — a bad
`HostKey` path, an `AuthorizedKeysCommand` that does not exist — would be
accepted, installed, and then handed to [BUG-3](#bug-3)'s broken watchdog.

**Fix that was not applied.** Check that the daemon that was asked for is the
daemon that answered, and stop the two features sharing a port:

```diff
--- a/lib/ssh_safety.sh
+++ b/lib/ssh_safety.sh
@@
-        if /usr/sbin/sshd -f "$_test_config_result"; then
-            sleep 2
+        rm -f /var/run/sshd_test.pid
+        /usr/sbin/sshd -f "$_test_config_result"
+        sleep 2
+        # sshd forks before it binds, so its exit status proves nothing;
+        # the pid file only appears once the listener is up
+        if [ -f /var/run/sshd_test.pid ]; then
```

```diff
--- a/config/defaults.conf.template
+++ b/config/defaults.conf.template
-EMERGENCY_SSH_PORT=2222      # Emergency SSH port number
+EMERGENCY_SSH_PORT=2223      # Emergency SSH port; must differ from SSHD_TEST_PORT
```

with the matching change to `emergency_ssh_port` in
`ansible/group_vars/all.yml:70`.

---

## BUG-21

**Status: Open, needs a decision.** Deferred by the fix pass: a provisional rename was reverted in [`689897e`](https://github.com/Bissbert/POSIX-hardening/commit/689897e) because it enabled an extra password-enabled SSH service; the name, the default and the port collision in BUG-20 need deciding together.

**`ENABLE_EMERGENCY_ACCESS` is never set outside Ansible, so the manual path's
emergency SSH fallback never runs.**
<a id="bug-21"></a>

`scripts/01-ssh-hardening.sh:108` gates the emergency daemon on a variable:

```sh
    if [ -n "$SSH_CONNECTION" ] || [ -n "$SSH_CLIENT" ]; then
        show_warning "Currently in SSH session - extra safety measures enabled"

        # Create emergency SSH access as fallback
        if [ "$ENABLE_EMERGENCY_ACCESS" = "1" ]; then
```

`ENABLE_EMERGENCY_ACCESS` is written by the two Ansible templates
(`ansible/templates/defaults.conf.j2:123` and
`ansible/roles/posix_hardening_deploy/templates/defaults.conf.j2:123`) and
nowhere else. It is absent from `config/defaults.conf.template`, absent from
`lib/common.sh`, and has no default at the use site. On the manual path — the
one `README.md` and `GETTING_STARTED.md` document, and the one `quick-start.sh`
sets up — the test compares the empty string to `1`, so the branch is dead.

The effect is that the safety measure the warning line announces is not taken.
`01-ssh-hardening.sh` prints `Currently in SSH session - extra safety measures
enabled` and then enables nothing.

**Reproduction**, section 2 of
[`media/captures/emergency-ssh.txt`](../media/captures/emergency-ssh.txt),
against a `config/defaults.conf` created from the shipped template exactly as
`quick-start.sh` creates it:

```text
=== 2. is ENABLE_EMERGENCY_ACCESS set by config/defaults.conf
    not present in config/defaults.conf
    the gate in scripts/01-ssh-hardening.sh:
      108:        if [ "$ENABLE_EMERGENCY_ACCESS" = "1" ]; then
    value seen by a script after sourcing the config:
      ENABLE_EMERGENCY_ACCESS=[]
```

`scripts/00-ssh-verification.sh` has the same shape one variable over: `:30`
reads `EMERGENCY_SSH_PORT="${EMERGENCY_SSH_PORT}"` with no default. That one
happens to be harmless, because `create_emergency_ssh_access` substitutes 2222
for an empty argument (`lib/ssh_safety.sh:485`) — but only by accident, and it
lands on the colliding port from [BUG-20](#bug-20).

**Verified:** that the variable is set only by the two Jinja templates, that it
is absent from the generated `config/defaults.conf`, and that it expands to the
empty string in a script that has sourced that config.

**Inferred by reading:** that `create_emergency_ssh_access` would otherwise
succeed on this path. It does succeed when called directly — section 3 of the
same capture — but the gated call site was not reached in a container, because
the capture runs `docker exec`, not an SSH session, so `$SSH_CONNECTION` is
empty too.

**Fix that was not applied:**

```diff
--- a/config/defaults.conf.template
+++ b/config/defaults.conf.template
 EMERGENCY_SSH_PORT=2222      # Emergency SSH port number
+ENABLE_EMERGENCY_ACCESS=1    # 1=open an emergency sshd before hardening SSH
```

and, so the gate cannot silently fail again if the config is absent:

```diff
--- a/scripts/01-ssh-hardening.sh
+++ b/scripts/01-ssh-hardening.sh
-        if [ "$ENABLE_EMERGENCY_ACCESS" = "1" ]; then
+        if [ "${ENABLE_EMERGENCY_ACCESS:-1}" = "1" ]; then
```

## BUG-22

**Status: Fixed in [`82b3581`](https://github.com/Bissbert/POSIX-hardening/commit/82b3581).**

**`ansible/playbooks/` holds a second, drifted copy of three playbooks, and the
copy under `playbooks/` cannot deploy the toolkit at all.**
<a id="bug-22"></a>

`site.yml`, `preflight.yml`, `rollback.yml` and `deploy_team_keys.yml` each
exist twice: once at the `ansible/` root and once under `ansible/playbooks/`.
Only `deploy_team_keys.yml` is identical in both places.

```text
=== 3. duplicated playbooks: root copy vs playbooks/ copy
    site.yml               differ: 3 changed hunks
    preflight.yml          differ: 4 changed hunks
    rollback.yml           differ: 14 changed hunks
    deploy_team_keys.yml   identical
```

Most of `rollback.yml`'s and `site.yml`'s drift is renamed `register:`
variables, which is harmless in itself but means neither file can be treated as
the authority. `preflight.yml` differs in behaviour, and that difference is
[BUG-23](#bug-23).

The `playbooks/` copy of `site.yml` also cannot run its deployment play.
Ansible resolves a `copy:` module's `src:` against the *playbook's* directory,
not the working directory, so every relative path in that file points at a
location that does not exist:

```text
=== 6b. do the relative src: paths in playbooks/site.yml resolve
    what playbooks/site.yml asks for, and whether it is there:
      ../lib/                    -> ansible/playbooks/../lib/                    MISSING
      ../scripts/                -> ansible/playbooks/../scripts/                MISSING
      ../tests/                  -> ansible/playbooks/../tests/                  MISSING
      ../orchestrator.sh         -> ansible/playbooks/../orchestrator.sh         MISSING
      ../emergency-rollback.sh   -> ansible/playbooks/../emergency-rollback.sh   MISSING
      templates/defaults.conf.j2 -> ansible/playbooks/templates/defaults.conf.j2 MISSING
    the same paths as the root copy resolves them:
      ../lib/                    -> ansible/../lib/                              present
      ../scripts/                -> ansible/../scripts/                          present
      templates/defaults.conf.j2 -> ansible/templates/defaults.conf.j2           present
```

**Reproduction**, sections 3 and 6b of
[`media/captures/ansible.txt`](../media/captures/ansible.txt). Section 6b also
builds a throwaway two-directory tree and runs a one-task playbook in it, so
the search path Ansible actually uses is printed rather than asserted:

```text
    controlled reproduction of the resolution rule, so the
    search path is visible rather than asserted:
        /ansible/playbooks/../lib/
        /ansible/playbooks/files/../lib/
        (cwd is not among them: ../lib/ is ansible/playbooks/../lib/)
```

`--syntax-check` passes on all ten playbooks in both locations, so nothing
catches this before a deployment run reaches the first `copy:` task.

**Verified:** that both copies exist and how they differ; that the paths listed
above are missing; and that Ansible 2.19.3 searches only `<playbook_dir>/files`
and `<playbook_dir>`, by running a minimal playbook and reading the error.

**Inferred by reading:** that `ansible/playbooks/site.yml` would fail at its
first `copy:` task. The reproduction shows the same task shape failing in an
isolated tree; the repository's own playbook was not run, because doing so
needs a managed host.

**Fix proposed at the time:** delete the stale copies, keeping the root ones
that `ansible/README.md` documents.

```diff
-ansible/playbooks/site.yml
-ansible/playbooks/preflight.yml
-ansible/playbooks/rollback.yml
-ansible/playbooks/deploy_team_keys.yml
```

If the `playbooks/` layout is the intended one instead, the four files have to
move rather than be copied, and every relative `src:` needs one fewer `../`.

## BUG-23

**Status: Fixed in [`5d377a3`](https://github.com/Bissbert/POSIX-hardening/commit/5d377a3).**

**`ansible/preflight.yml` starts services while claiming to inspect them.**
<a id="bug-23"></a>

`ansible/preflight.yml:201-211`, in a block named `Check Running Services`:

```yaml
    - name: Get list of running services
      ansible.builtin.systemd:
        name: "{{ item }}"
        state: started
      register: critical_services
      failed_when: false
      loop:
        - ssh
        - sshd
```

`state: started` is not a query. On a host where `ssh` or `sshd` is stopped —
deliberately, or because the host is mid-maintenance — a pre-flight check
starts it. The playbook's whole purpose is to report on a host before anything
is changed, and `ansible/README.md:93` presents it that way (`ansible-playbook
preflight.yml`).

The copy at `ansible/playbooks/preflight.yml:203-205` does not have this
problem; it uses `ansible.builtin.systemd_service` with no `state:`, which only
reports. The two files have drifted ([BUG-22](#bug-22)), and the root copy —
the documented one — is the one that changes the host.

**Reproduction**, section 3 of
[`media/captures/ansible.txt`](../media/captures/ansible.txt), which prints the
diff between the two copies.

**Verified:** that the task is present with `state: started`, that the other
copy lacks it, and that `ansible/README.md` documents the root copy as a
read-only pre-flight step.

**Inferred by reading:** that a stopped `ssh` would actually be started. This
was not executed: `preflight.yml` needs a managed host, and the one throwaway
container used for the other captures has no systemd.

**Fix proposed at the time:**

```diff
--- a/ansible/preflight.yml
+++ b/ansible/preflight.yml
-        - name: Get list of running services
-          ansible.builtin.systemd:
+        - name: Check critical services
+          ansible.builtin.systemd_service:
             name: "{{ item }}"
-            state: started
           register: critical_services
```

## BUG-24

**Status: Open, needs a decision.** Deferred by the fix pass: each kind of change (files, live kernel state, firewall, services, accounts) needs its own undo guarantee, or an explicit statement that it is not reversible.

**Twenty of the twenty-one hardening scripts register nothing for rollback, so
their transactions roll back to nothing.**
<a id="bug-24"></a>

`lib/rollback.sh` exports five functions that push an undo action onto the
transaction stack: `register_file_rollback`, `register_command_rollback`,
`register_service_rollback`, `register_firewall_rollback` and
`register_sysctl_rollback`. Across all of `scripts/` they are called once:

```text
=== 3. summary
    scripts in scripts/:                     21
    scripts that open a transaction:         11
    register_* calls in all of scripts/:     1
    the one script that registers anything, and what:
      scripts/02-firewall-setup.sh:94:    register_command_rollback "iptables-restore < $backup_file"
```

Eleven scripts open a transaction, twelve commit one, nine call
`rollback_transaction` on a failure path — and only `02-firewall-setup.sh` ever
puts anything on the stack to undo. `scripts/01-ssh-hardening.sh` alone has
four `rollback_transaction` calls (`:310`, `:323`, `:358`, `:373`) and no
`register_*` call at all.

The per-script breakdown is section 2 of
[`media/captures/rollback-coverage.txt`](../media/captures/rollback-coverage.txt):

```text
    script                     begin commit rollback register
    00-ssh-verification.sh         1      1        3        0
    01-ssh-hardening.sh            1      2        4        0
    02-firewall-setup.sh           1      1        1        1
    ...
    TOTAL over 21 scripts         11     12        9        1
```

`rollback_transaction` on an empty stack takes the `Cleared` path — it logs
`Rollback completed` and returns 0 with nothing undone. That is the same
observable outcome as [BUG-5](#bug-5), reached for a different reason, and it
is why the measured `03-kernel-params.sh` failure in
[`media/captures/03-kernel-params.log`](../media/captures/03-kernel-params.log)
restored nothing even though the transaction machinery ran correctly.

This is distinct from [BUG-3](#bug-3). BUG-3 is that the one backup path a
script does capture arrives corrupted; BUG-24 is that for twenty of the
twenty-one scripts there is no backup path to corrupt, because none is ever
registered. Fixing BUG-3 alone would not make rollback restore anything for
those twenty scripts.

Ten scripts — `07`, `09`, `12`, `13`, `15`, `16`, `17`, `18`, `19`, `20` — open
no transaction at all, so for those the toolkit's rollback documentation
describes machinery that is not engaged on their behalf in any form.

**Reproduction:** [`tools/capture-rollback-coverage.sh`](../tools/capture-rollback-coverage.sh),
which greps the repository and runs nothing.

**Verified:** the counts above, and that every count is a real call rather than
a comment or a definition (the grep output names file and line for each).

**Inferred by reading:** that `rollback_transaction` therefore restores nothing
in those twenty scripts. The empty-stack path itself is read from
`lib/rollback.sh`, not separately instrumented; the one failing script that was
run in a container (`03-kernel-params.sh`) is consistent with it.

**Fix that was not applied:** there is no one-line diff for this. Every script
that modifies a file needs to capture a backup and register it before the
modification, in the shape `02-firewall-setup.sh` already uses. For
`01-ssh-hardening.sh` the smallest version is:

```diff
--- a/scripts/01-ssh-hardening.sh
+++ b/scripts/01-ssh-hardening.sh
     begin_transaction "ssh_hardening"
+    _sshd_backup=$(safe_backup_file "/etc/ssh/sshd_config")
+    register_file_rollback "/etc/ssh/sshd_config" "$_sshd_backup"
```

which also depends on [BUG-3](#bug-3) being fixed first, or `$_sshd_backup`
arrives with a log line glued to the front of it.

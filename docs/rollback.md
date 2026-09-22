# Rollback: the transaction model, and what it does not undo

[← back to the documentation index](README.md)

`lib/rollback.sh` is the safety story of this toolkit. Every hardening script
opens a transaction, registers an undo action before each change, and relies on
an `EXIT` trap to replay those actions in reverse if anything fails. This page
describes that machinery and then shows, from a captured run, that the file
restore at the end of it does not currently work.

## The state machine

```mermaid
stateDiagram-v2
    [*] --> Idle

    Idle --> Open: begin_transaction<br/>clears the stack, writes the id<br/>traps EXIT INT TERM

    Open --> Open: register_file_rollback<br/>register_command_rollback<br/>register_service_rollback<br/>register_sysctl_rollback<br/>register_firewall_rollback

    Open --> Committed: script exits 0<br/>commit_transaction
    Open --> Rolling: script exits non-zero<br/>and ROLLBACK_ENABLED is 1
    Open --> Abandoned: script exits non-zero<br/>and ROLLBACK_ENABLED is unset

    Rolling --> Replaying: stack is non-empty<br/>reversed with posix_reverse
    Rolling --> Cleared: stack is empty

    Replaying --> Cleared: every action attempted<br/>failures only logged

    Cleared --> Idle: logs Rollback completed<br/>returns 0 unconditionally
    Committed --> Idle: stack cleared, trap removed
    Abandoned --> Idle: trap fires, nothing happens

    state Replaying {
        [*] --> FILE_RESTORE
        [*] --> COMMAND
        [*] --> SERVICE
        [*] --> SYSCTL
        [*] --> FIREWALL
    }
```

Three transitions in that diagram are where the risk lives, and each is a
separate defect:

| Transition | What is wrong |
|---|---|
| `Open --> Abandoned` | `ROLLBACK_ENABLED` has no default, so without `config/defaults.conf` the trap runs and does nothing ([BUG-4](BUGS-FOUND.md#bug-4)) |
| inside `Replaying` | `FILE_RESTORE` is handed a backup path with a log line glued to the front, so it restores nothing ([BUG-3](BUGS-FOUND.md#bug-3)) |
| `Cleared --> Idle` | `rollback_transaction` logs `Rollback completed` and returns 0 whether or not any action succeeded ([BUG-5](BUGS-FOUND.md#bug-5)) |

## What a rollback action looks like

The stack at `/var/lib/hardening/rollback_stack` is a flat text file, one
action per line, `TYPE|DATA`:

| Type | `DATA` | Replayed by |
|---|---|---|
| `FILE_RESTORE` | `backup_path:original_path` | `cp -p` back over the original |
| `COMMAND` | a shell command | `eval` |
| `SERVICE` | `name:start`, `name:stop`, `name:restart`, `name:reload` | `safe_service_<action>` |
| `SYSCTL` | `parameter:value` | `sysctl -w` |
| `FIREWALL` | a shell command | `eval`, if `iptables` exists |

`rollback_transaction` moves the stack aside, reverses it with `posix_reverse`,
and calls `execute_rollback_action` for each line. Failures are logged and
ignored; there is no second attempt and no error propagation.

## The registration path, and where it breaks

```mermaid
flowchart TD
    S["a hardening script"] --> SB["safe_backup_file /etc/thing"]
    SB --> LOG["log INFO 'Backed up …'<br/>written to STDOUT"]
    SB --> ECHO["echo the backup path<br/>written to STDOUT"]
    LOG --> CAP["_backup=$(safe_backup_file …)<br/>captures BOTH lines"]
    ECHO --> CAP
    CAP --> REG["register_file_rollback /etc/thing $_backup"]
    REG --> STACK["line 1: FILE_RESTORE then the log line<br/>line 2: the path, then :/etc/thing"]
    STACK --> RB["rollback reads the stack<br/>one line at a time"]
    RB --> L1["line 1: type FILE_RESTORE,<br/>data is the log text"]
    RB --> L2["line 2: type is the backup path,<br/>matches no case arm"]
    L1 --> E1["ERROR Backup file not found"]
    L2 --> E2["ERROR Unknown rollback action type"]
    E1 --> DONE["INFO Rollback completed<br/>return 0"]
    E2 --> DONE

    style SB fill:#1f6feb,color:#fff
    style LOG fill:#9e6a03,color:#fff
    style CAP fill:#da3633,color:#fff
    style E1 fill:#da3633,color:#fff
    style E2 fill:#da3633,color:#fff
    style DONE fill:#238636,color:#fff
```

The green box at the bottom is the point. The run reports success.

## A rollback, captured

`tools/capture-rollback-demo.sh` builds a throwaway container, creates
`/etc/demo.conf`, backs it up through the toolkit's own functions, modifies it,
and rolls the transaction back. Full output:
[`media/captures/rollback-demo.log`](../media/captures/rollback-demo.log).

![A recorded rollback in a container: the backup path is captured with a log
line in front of it, the rollback stack is split across two lines, both
rollback actions fail, and the hardened content survives.](../media/rollback-demo.gif)

The two lines that explain everything:

```text
== what safe_backup_file actually returns ==
     1	[INFO] Backed up /etc/demo.conf to /var/backups/hardening/demo.conf.20260921-195638.bak
     2	/var/backups/hardening/demo.conf.20260921-195638.bak
lines captured: 2
names an existing file: NO
```

and the result:

```text
== after rollback ==
HARDENED - this must not survive the rollback

RESULT: file was NOT restored - the hardened content survived
```

This is not specific to the demo file. The same sequence appears in the
captured `03-kernel-params.sh` run
([`media/captures/03-kernel-params.log`](../media/captures/03-kernel-params.log)),
where the stray path is visible on its own line and the hardening block was
still in `/etc/sysctl.conf` after `Rollback completed`.

## How much of the toolkit is actually inside a transaction

The section above is about a registration that arrives corrupted. There is a
larger question underneath it: how often does a hardening script register
anything at all?

Once. `tools/capture-rollback-coverage.sh` counts both sides of the API across
`scripts/`:

```text
    script                     begin commit rollback register
    00-ssh-verification.sh         1      1        3        0
    01-ssh-hardening.sh            1      2        4        0
    02-firewall-setup.sh           1      1        1        1
    03-kernel-params.sh            1      1        0        0
    04-network-stack.sh            1      1        0        0
    05-file-permissions.sh         1      1        0        0
    06-process-limits.sh           1      1        0        0
    07-audit-logging.sh            0      0        0        0
    08-password-policy.sh          1      1        0        0
    09-account-lockdown.sh         0      0        0        0
    10-sudo-restrictions.sh        1      1        0        0
    11-service-disable.sh          1      1        1        0
    12-tmp-hardening.sh            0      0        0        0
    13-core-dump-disable.sh        0      0        0        0
    14-sysctl-hardening.sh         1      1        0        0
    15-cron-restrictions.sh        0      0        0        0
    16-mount-options.sh            0      0        0        0
    17-shell-timeout.sh            0      0        0        0
    18-banner-warnings.sh          0      0        0        0
    19-log-retention.sh            0      0        0        0
    20-integrity-baseline.sh       0      0        0        0
    TOTAL over 21 scripts         11     12        9        1
```

Full output:
[`media/captures/rollback-coverage.txt`](../media/captures/rollback-coverage.txt).

```mermaid
flowchart TD
    ALL["21 scripts in scripts/"]
    ALL --> NOTX["10 open no transaction<br/>07 09 12 13 15 16 17 18 19 20"]
    ALL --> TX["11 open a transaction"]
    TX --> EMPTY["10 register nothing<br/>stack stays empty"]
    TX --> ONE["1 registers an undo action<br/>02-firewall-setup.sh:94"]

    EMPTY --> OUT1["rollback_transaction logs<br/>Rollback completed, undoes nothing"]
    ONE --> OUT2["one iptables-restore<br/>is replayed"]

    style ALL fill:#8250df,color:#fff
    style NOTX fill:#da3633,color:#fff
    style EMPTY fill:#da3633,color:#fff
    style OUT1 fill:#da3633,color:#fff
    style ONE fill:#238636,color:#fff
    style OUT2 fill:#238636,color:#fff
```

`scripts/01-ssh-hardening.sh` is the clearest case. It calls
`rollback_transaction` on four separate failure paths — a failed config update,
lost connectivity, failed validation, failed verification — and registers
nothing on any of them. Each of those four calls reaches
`rollback_transaction` with an empty stack, takes the `Cleared` transition in
the state machine at the top of this page, logs `Rollback completed` and
returns 0.

This is [BUG-24](BUGS-FOUND.md#bug-24), and it matters more than
[BUG-3](BUGS-FOUND.md#bug-3): fixing the corrupted backup path would make
rollback work for the one script that registers something. The other twenty
would still roll back to nothing, because there is nothing on their stacks to
correct.

## What still works

The transaction bookkeeping around the broken part is sound, and worth keeping
in mind when reading the fix:

- The `EXIT INT TERM` trap is installed by `begin_transaction` and removed by
  `commit_transaction`, so an interrupted script does attempt a rollback.
- The stack is cleared at the start of every transaction, so a stale stack from
  a previous run is not replayed.
- `SYSCTL`, `COMMAND`, `SERVICE` and `FIREWALL` actions are not affected by
  [BUG-3](BUGS-FOUND.md#bug-3); their `DATA` does not come from a command
  substitution around a logging function. They were not exercised by any
  capture in this pass, so this page says only that the defect does not reach
  them, not that they work.
- `posix_reverse` in `lib/posix_compat.sh` is a correct POSIX reversal and is
  used by `rollback_transaction`.

## The manual escape hatch

`emergency-rollback.sh` exists to restore backups without the rest of the
toolkit. It aborts on its second statement, because it tries to `export
SAFETY_MODE=0` after `lib/common.sh` has already made `SAFETY_MODE` read-only
([BUG-2](BUGS-FOUND.md#bug-2)):

```text
emergency-rollback.sh: 14: export: SAFETY_MODE: is read only
```

Until that is fixed, restoring a file by hand from `/var/backups/hardening/`
with `cp -p` is the reliable path. The backups themselves are written
correctly, with `.meta` and `.sha256` sidecars; it is only the path handed to
the rollback machinery that is malformed.

## Checkpoints

`create_checkpoint` and `rollback_to_checkpoint` are defined in
`lib/rollback.sh` and called from nowhere. They are not part of any documented
workflow and, as written, would not replay their actions
([BUG-17](BUGS-FOUND.md#bug-17)). Treat the checkpoint API as unimplemented.

See [measurement.md](measurement.md) for how the captures on this page were
produced, and [BUGS-FOUND.md](BUGS-FOUND.md) for the diffs that would fix what
it shows.

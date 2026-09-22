# POSIX Shell Server Hardening Toolkit

A set of POSIX `sh` scripts that harden a Debian server over SSH, plus an
Ansible tree that does the same thing across a fleet. The design goal that
shapes every part of it is not locking the operator out: SSH changes are
validated against a throwaway daemon on port 2222, a watchdog reverts the
configuration if the connection dies, and each script opens a transaction that
is meant to undo its own changes on failure. This README documents what the
code does today, measured in a container, rather than what it is designed to
do — and the two differ enough that the difference is the first thing below.

## What a run does, and where it stops

```mermaid
flowchart TD
    START["sudo sh orchestrator.sh --all"] --> L["lib/common.sh<br/>lib/rollback.sh<br/>lib/ssh_safety.sh"]
    L --> BUG1["lib/rollback.sh:8 resolves<br/>posix_compat.sh against the<br/>caller's directory, not lib/"]
    BUG1 --> EXIT["exit 2, nothing done<br/>on a clean clone"]

    BUG1 -. "with tools/bug-workarounds.patch" .-> P1["priority 1<br/>SSH, firewall"]
    P1 --> P2["priority 2<br/>kernel, network, files"]
    P2 --> P3["priority 3<br/>accounts, sudo, PAM"]
    P3 --> P4["priority 4<br/>audit, banners, integrity"]
    P4 --> SUM["summary:<br/>Completed: 0  Failed: 0"]

    style START fill:#8250df,color:#fff
    style BUG1 fill:#da3633,color:#fff
    style EXIT fill:#da3633,color:#fff
    style P1 fill:#1f6feb,color:#fff
    style P2 fill:#1f6feb,color:#fff
    style P3 fill:#1f6feb,color:#fff
    style P4 fill:#1f6feb,color:#fff
    style SUM fill:#9e6a03,color:#fff
```

Both red boxes and the amber one were observed, not inferred. On an unpatched
clone every documented entry point exits 2 before doing any work
([`media/captures/pristine.txt`](media/captures/pristine.txt)); with the
workaround applied, `orchestrator.sh --all` ran 13 of its 20 declared scripts
and then reported `Completed: 0  Failed: 0`
([`media/captures/orchestrator.log`](media/captures/orchestrator.log)).

All 24 defects behind that picture are written up, with reproductions and with
the diff that would fix each one, in
[`docs/BUGS-FOUND.md`](docs/BUGS-FOUND.md). Nothing in the toolkit's source was
changed to produce this documentation.

## Quick start

Everything in this section was run on macOS 15 (arm64) with Docker 24.0.7 and
produced the output committed under `media/captures/`.

### See what a clean clone does

```sh
git clone https://github.com/Bissbert/POSIX-hardening.git
cd POSIX-hardening
sh tools/static-analysis.sh .
```

`static-analysis.sh` is read-only: it runs the same syntax and lint gates the
CI runs and prints a Markdown report. It needs `dash`, `bash`, `busybox`,
`shellcheck` and `checkbashisms` on `PATH`; if you do not have them,

```sh
sh tools/analysis-env.sh
```

builds a throwaway `debian:12-slim` container that does, runs the same script
inside it, and removes the container afterwards. Nothing is installed on the
host.

### Watch it harden something, safely

```sh
sh tools/container-image.sh          # build a throwaway Debian 12 target
sh tools/capture-hardening-run.sh    # run three hardening scripts inside it
sh tools/capture-rollback-demo.sh    # open a transaction and roll it back
sh tools/capture-ssh-watchdog.sh     # trip the SSH lockout watchdog
```

Each tool builds its own container, copies the repository in, runs, writes its
transcript to `media/captures/`, and destroys the container. **Do not point
them at a host you care about**: the scripts they run rewrite `/etc/ssh`,
`/etc/sysctl.conf`, PAM configuration and firewall rules in place.

These tools apply [`tools/bug-workarounds.patch`](tools/bug-workarounds.patch)
to the container's copy of the source, because without it nothing starts. The
patch changes where two libraries look for a sibling file and the order of two
statements in `emergency-rollback.sh`. It changes no hardening logic.

### Harden an actual server

Not yet, without patching. On a clean clone `sudo sh orchestrator.sh` and
`sudo sh scripts/NN-*.sh` both exit 2 on
[BUG-1](docs/BUGS-FOUND.md#bug-1) before doing anything, and `quick-start.sh`
ends by invoking the orchestrator, so it reaches the same wall. The Ansible
path copies the same `lib/` to the managed host and hits it there instead.
[`docs/deployment-paths.md`](docs/deployment-paths.md) compares the three
paths and says what each one would do once it can start.

## Architecture

```mermaid
flowchart TD
    subgraph entry["entry points"]
        ORCH["orchestrator.sh<br/>20 entries in SCRIPT_ORDER"]
        QS["quick-start.sh<br/>interactive"]
        SITE["ansible/site.yml<br/>copies the repo, runs the scripts"]
        MASTER["ansible/hardening_master.yml<br/>21 roles, no scripts"]
    end

    subgraph scripts["scripts/ — 21 numbered scripts"]
        S["00-ssh-verification … 20-integrity-baseline"]
    end

    subgraph lib["lib/ — 5 libraries"]
        COMMON["common.sh<br/>logging, config, markers"]
        RB["rollback.sh<br/>transactions, undo stack"]
        SSH["ssh_safety.sh<br/>test daemon, watchdog"]
        BK["backup.sh<br/>timestamped backups"]
        PC["posix_compat.sh<br/>portability helpers"]
    end

    subgraph state["state on disk"]
        BACKUPS["/var/backups/hardening"]
        STACK["/var/lib/hardening/rollback_stack"]
        MARKERS["/var/lib/hardening/completed"]
        LOGS["/var/log/hardening"]
    end

    ORCH --> S
    QS --> S
    SITE --> S
    MASTER --> ROLES["ansible/roles/posix_hardening_*"]

    S --> COMMON
    S --> RB
    S --> SSH
    COMMON --> PC
    RB --> PC
    SSH --> PC
    RB --> BK

    BK --> BACKUPS
    RB --> STACK
    COMMON --> MARKERS
    COMMON --> LOGS

    style ORCH fill:#1f6feb,color:#fff
    style QS fill:#1f6feb,color:#fff
    style SITE fill:#8250df,color:#fff
    style MASTER fill:#8250df,color:#fff
    style S fill:#238636,color:#fff
    style ROLES fill:#8250df,color:#fff
    style COMMON fill:#9e6a03,color:#fff
    style RB fill:#9e6a03,color:#fff
    style SSH fill:#9e6a03,color:#fff
    style BK fill:#9e6a03,color:#fff
    style PC fill:#9e6a03,color:#fff
```

The two Ansible entry points do not overlap: `site.yml` copies the shell
toolkit to the managed host and runs `scripts/NN-*.sh` over SSH, while
`hardening_master.yml` ignores the scripts entirely and applies 21 roles.
Both are maintained; they are not two views of one thing.
[`docs/deployment-paths.md`](docs/deployment-paths.md) has the details, and
[`docs/library-reference.md`](docs/library-reference.md) covers the load order
of `lib/`, which is where BUG-1 lives.

## Claimed capabilities, and what was measured

| Capability | Claimed in the source | Measured |
|---|---|---|
| Works on `dash`, `ash`, BusyBox `sh` | "100% POSIX compliant, no bash required" | `dash -n`, `bash -n` and `busybox sh -n` accept all 29 files in the CI set. `shellcheck -s sh` reports `local` (SC3043) 74 times, all in `orchestrator.sh`, `scripts/` and `ansible/utils/`; `lib/` is clean |
| Never locks you out of SSH | "multiple safety mechanisms" | The watchdog fires and restores `sshd_config` — captured. The config test that gates it passes whenever anything holds port 2222, including the toolkit's own emergency daemon ([BUG-20](docs/BUGS-FOUND.md#bug-20)) |
| Automatic rollback on failure | "all operations wrapped in transactions" | 11 of 21 scripts open a transaction; 1 of 21 registers an undo action. A rollback with an empty stack logs `Rollback completed` and undoes nothing ([BUG-24](docs/BUGS-FOUND.md#bug-24)) |
| Every change backed up | "timestamped backups of all modified files" | Backups are written correctly, with `.meta` and `.sha256` sidecars. The path handed to the rollback machinery has a log line glued to the front, so the restore finds no file ([BUG-3](docs/BUGS-FOUND.md#bug-3)) |
| Idempotent | "scripts can be run multiple times safely" | Not measured. Every capture starts from a fresh container |
| Dry-run mode | `DRY_RUN=1` | A dry run writes the completion marker, so the real run is then skipped ([BUG-13](docs/BUGS-FOUND.md#bug-13)); and `config/defaults.conf` overrides the environment, so with a config file present `DRY_RUN=1` is discarded ([BUG-14](docs/BUGS-FOUND.md#bug-14)) |
| CI/CD tested | ShellCheck, checkbashisms, ansible-lint | The ShellCheck gate (`-S error`) finds 0 issues over 31 files and `checkbashisms` 0 over 29 — both gates pass. `ansible-lint` reports 1394 findings in 138 files; the `min` profile passes and `production` does not |

## Measured results

### Static analysis

Reproduce with `sh tools/static-analysis.sh .`, or in a container with
`sh tools/analysis-env.sh`.

| Measurement | Value |
|---|---|
| Files in the CI syntax set | 29 |
| `dash -n` / `bash -n` / `busybox sh -n` failures | 0 / 0 / 0 |
| `checkbashisms` files with findings | 0 of 29 |
| ShellCheck at the CI gate (`-S error -s sh`) | 0 findings over 31 files |
| `SC3043` (`local` is undefined in POSIX `sh`) | 74, none under `lib/` |
| `SC3012` (lexicographical `\>`) | 2 |
| Numbered scripts / libraries / Ansible roles | 21 / 5 / 23 |
| Entries in `orchestrator.sh` `SCRIPT_ORDER` | 20 |
| Files tracked by git | 283 |
| Shell bytes in the CI file set | 180,365 |

### A hardening run

`sh tools/capture-hardening-run.sh`, inside the throwaway container:

| Script | Exit | Output lines |
|---|---|---|
| `scripts/01-ssh-hardening.sh` | 0 | 129 |
| `scripts/03-kernel-params.sh` | 1 | 18 |
| `scripts/05-file-permissions.sh` | 0 | 16 |

The effects were read back with `sshd -T` rather than taken from the script's
own output: all eleven advertised SSH settings were in place and port 22 was
still answering
([`media/captures/effects.txt`](media/captures/effects.txt)).
`03-kernel-params.sh` exits 1 because one sysctl key cannot be set in a
container and `sysctl -p` is fatal under `set -e`
([BUG-6](docs/BUGS-FOUND.md#bug-6)); it may well succeed on a real host.

### The SSH watchdog, recorded

![A recorded run of the SSH lockout watchdog in a container: the watchdog
starts, the connectivity probe fails, and sshd_config is restored from the
backup before the timeout expires.](media/ssh-watchdog.gif)

Every frame is a line from
[`media/captures/ssh-watchdog.log`](media/captures/ssh-watchdog.log), in order.
Nothing is typed or staged. [`docs/ssh-safety.md`](docs/ssh-safety.md) walks
through the decision flow this exercises.

### A rollback, recorded

![A recorded rollback in a container: the backup path is captured with a log
line in front of it, the rollback stack is split across two lines, both
rollback actions fail, and the hardened content survives while the run reports
success.](media/rollback-demo.gif)

From [`media/captures/rollback-demo.log`](media/captures/rollback-demo.log).
The file was not restored and the run reported `Rollback completed`.
[`docs/rollback.md`](docs/rollback.md) explains the state machine and how much
of the toolkit is inside a transaction at all.

Every number on this page, the command that produced it, and the list of what
could not be measured are in
[`docs/measurement.md`](docs/measurement.md).

## Repository layout

```text
.
├── orchestrator.sh              # runs the numbered scripts in priority order
├── quick-start.sh               # interactive installer
├── emergency-rollback.sh        # manual restore, outside the toolkit
├── lib/                         # 5 POSIX sh libraries
│   ├── common.sh                # logging, config loading, completion markers
│   ├── rollback.sh              # transactions and the undo stack
│   ├── ssh_safety.sh            # test daemon, watchdog, emergency access
│   ├── backup.sh                # timestamped backups with checksums
│   └── posix_compat.sh          # portability helpers
├── scripts/                     # 21 numbered hardening scripts, 00 … 20
├── config/                      # defaults.conf.template, firewall.conf.example
├── tests/                       # validation_suite.sh and friends
├── ansible/
│   ├── site.yml                 # copies the toolkit out and runs the scripts
│   ├── hardening_master.yml     # applies 21 roles instead
│   ├── roles/                   # 23 posix_hardening_* roles
│   └── playbooks/               # a second, drifted copy of four playbooks
├── docs/                        # see docs/README.md for the index
├── tools/                       # the scripts that produced every number here
└── media/
    ├── captures/                # raw transcripts, one per tool
    └── *.gif                    # rendered from those transcripts
```

`tools/` and `media/` were added by this documentation pass. Everything else
is the project's own.

## Known limitations

Measured, in a container, on Debian 12 arm64. Each item links to a full entry
with a reproduction and a proposed diff.

**The toolkit does not start on a clean clone**

- Every documented entry point exits 2: `lib/rollback.sh:8` and
  `lib/ssh_safety.sh:8` resolve `posix_compat.sh` against `$0`'s directory
  rather than `lib/` ([BUG-1](docs/BUGS-FOUND.md#bug-1)).
- `emergency-rollback.sh` aborts on line 14, exporting a variable
  `lib/common.sh` has already made read-only
  ([BUG-2](docs/BUGS-FOUND.md#bug-2)).
- With `config/defaults.conf` present, `orchestrator.sh` cannot start at all,
  and `--dry-run` aborts on the same class of error
  ([BUG-7](docs/BUGS-FOUND.md#bug-7), [BUG-8](docs/BUGS-FOUND.md#bug-8)).
- `--priority N` runs nothing and exits 0
  ([BUG-15](docs/BUGS-FOUND.md#bug-15)).

**The safety net does not catch**

- 20 of 21 scripts open transactions but register no undo actions, so their
  rollback stack is empty and `Rollback completed` means nothing was undone
  ([BUG-24](docs/BUGS-FOUND.md#bug-24)).
- Backup paths are captured together with a log line, so the one registration
  that does exist cannot find its file
  ([BUG-3](docs/BUGS-FOUND.md#bug-3)).
- Without `config/defaults.conf`, automatic rollback is silently disabled
  ([BUG-4](docs/BUGS-FOUND.md#bug-4)).
- `rollback_transaction` returns 0 whether or not every action in it failed
  ([BUG-5](docs/BUGS-FOUND.md#bug-5)).

**Wrong results rather than no results**

- A dry run writes the completion marker, so the subsequent real run is
  skipped ([BUG-13](docs/BUGS-FOUND.md#bug-13)).
- `config/defaults.conf` is sourced after the environment and overrides it, so
  `DRY_RUN=1 sh scripts/…` does nothing
  ([BUG-14](docs/BUGS-FOUND.md#bug-14)).
- `FAIL_FAST` abandons the rest of one priority level and then continues with
  the next ([BUG-16](docs/BUGS-FOUND.md#bug-16)).
- The live-daemon SSH config test passes whenever anything holds port 2222 —
  including the toolkit's own emergency daemon
  ([BUG-20](docs/BUGS-FOUND.md#bug-20)).
- A fresh clone ships public keys nobody holds the private half of, and the
  Ansible path deploys them ([BUG-18](docs/BUGS-FOUND.md#bug-18)).
- Dependency checks in `orchestrator.sh` never block and never match, and the
  final summary always counts zero
  ([BUG-9](docs/BUGS-FOUND.md#bug-9)).

**Nine further entries**, including two drifted Ansible playbook copies
that cannot resolve their own sources, a pre-flight check that starts services
instead of reporting on them, and disagreeing script counts and version
numbers across the documentation. See the severity table at the top of
[`docs/BUGS-FOUND.md`](docs/BUGS-FOUND.md).

**Limits of this evidence**

- Only Debian 12 on arm64 was tested. RHEL and Alpine are claimed and were not
  tested.
- Only 4 of the 21 hardening scripts were executed.
- No Ansible task was run against any host. The playbooks were parsed
  (`--syntax-check`) and read, not applied.
- Every capture is local to a container. The lockout guarantees concern a
  remote operator's SSH session, and that scenario was not reproduced.
- Idempotence and performance were not measured at all.

## Documentation

[`docs/README.md`](docs/README.md) is the index. The pages written with
measurements behind them are
[execution-model](docs/execution-model.md),
[ssh-safety](docs/ssh-safety.md),
[rollback](docs/rollback.md),
[deployment-paths](docs/deployment-paths.md),
[library-reference](docs/library-reference.md),
[BUGS-FOUND](docs/BUGS-FOUND.md) and
[measurement](docs/measurement.md).

## License

MIT — see [LICENSE](LICENSE).

## Version

`VERSION` says 1.1.0. `lib/common.sh:10` declares `VERSION="1.0.0"` and
`docs/releases/CHANGELOG.md` has no 1.1.0 entry
([BUG-12](docs/BUGS-FOUND.md#bug-12)).

# CLAUDE.md

**When changing commands, options, or behavior: always update CLAUDE.md, README.md, and `cmd_help()` in `ccs` together. Run `./test.sh` to verify.**

## Project overview

`ccs` (Claude Code Switch) is a minimal POSIX sh script for switching Claude Code between AI providers — including a `[claude]` provider that switches to *nothing*, i.e. claude on its own login — for backing up the `~/.claude` config that makes a good install, and for keeping the machine awake while a session runs. It is a **sidecar tool** — `claude` always works as-is. Provider switching only injects env vars into the child process spawned when running `ccs` (defaults to launch); the two commands that do write to `~/.claude` are listed under Core principle below.

## Core principle

**`claude` must always work on its own.** `ccs` never modifies the user's shell, dotfiles, or Claude Code config. All state lives in `~/.claude-provider/` and env vars only exist inside the `ccs` subprocess (`exec env ... claude`).

**Two exceptions, both opt-in:**

1. `ccs notify on|off` edits `~/.claude/settings.json` (hooks + `preferredNotifChannel`). Backed up to `~/.claude-provider/settings-backup.json`, fully reversed by `notify off`. Requires jq.
2. `ccs sync pull|import` writes into `~/.claude`, restricted to `$SYNC_PATHS`; `ccs sync hooks on` adds `SessionStart`/`SessionEnd` entries to `~/.claude/settings.json`. Every write is preceded by a snapshot into `~/.claude-provider/sync-backup/<timestamp>/`. Requires git.

`purge` detaches both hook families before deleting anything — but never lets that stop it. The
guard is a `grep` for the hook marker, so a hand-edited `settings.json` with a trailing comma still
reaches `jq`, which exits non-zero and used to kill `purge` under `set -e` before it removed a
thing. It now checks validity first and says what the user has to clean up by hand.

## Architecture

- **Single script**: `ccs` (~2500 lines of POSIX sh)
- **Config**: INI format at `~/.claude-provider/config`, parsed with shell builtins (`while read` +
  `case` + parameter expansions). The header arm matches on the opening bracket, not on the line
  ending in one: `[zai]  # main` used to match no arm at all and be dropped silently, leaving every
  key beneath it attributed to the previous section — a credential written into another vendor's
  provider, with `ccs status` reporting nothing wrong. Anything after `]` is a trailing comment, a
  header with no closing bracket warns, and a section repeated in the file is one provider. **No `sed`/`cut` in `parse_config`**: it runs on every launch and a
  fork per line cost ~400 ms on a 100-line config. Spaces around `=` are trimmed, same rule as
  `config_set`. `write_defaults` is one `awk` pass for the same reason
- **State**: `~/.claude-provider/active` stores the current provider and model, plus `NATIVE=` for
  the native login (removed by `ccs reset`). **Nothing else**: key, `base_url` and tier models are
  re-read from the config by `load_state` at every launch through `resolve_provider`, so editing
  the config is enough and no second copy of a key sits on disk. Files written by older versions
  still carry `API_KEY=`/`BASE_URL=`; `read_active` keeps reading them and they win only when the
  provider has since vanished from the config. A blanked key on the active provider is an error at
  launch (the provider was chosen explicitly), unlike the `[_defaults]` path which stays vanilla
- **Model cache**: `~/.claude-provider/models-cache` stores resolved context windows (survives
  `reset`, removed by `purge`). `model=auto` picks live in the same file under `<spec>#<tier>` keys
  with their own 24 h TTL (`MODELS_CACHE_AUTO_TTL`)
- **Sync state**: `~/.claude-provider/sync/` (git working copy), `sync-backup/<timestamp>/`
  (pre-restore snapshots), `sync-state` (last sync epoch + commit). All survive `reset`, all
  removed by `purge`
- **No language runtimes**: no python, no node. Four CLI dependencies, none fatal: `jq` (notify,
  and settings.json handling in sync), `llm-models` (context windows), `git` (sync), `gh` (only
  `sync init --gist-new` / `--repo-new`). All degrade gracefully at runtime so a manual `curl`
  install still works
- **Zero footprint**: `ccs reset` or `ccs purge` removes all traces

## Native login (`[claude]`, `native=true`)

- The default provider on a fresh install, and the one that configures **nothing**: no
  `ANTHROPIC_BASE_URL`, no key, no model, no window. `cmd_launch` gets a third branch that is pure
  `env -u ... $CAFFEINE_CMD claude "$@"`. Launching through `ccs` becomes indistinguishable from
  running `claude`, which is what makes keep-awake and sync usable on a Claude subscription
- **It is a config key, not a hardcoded section name.** `is_native()` reads `native=true`, so any
  section can be one and adding another stays "add a section". A native section ignores
  `base_url=`, `api_key=` and `model=` — there is nothing to inject
- `NATIVE=` is persisted in `~/.claude-provider/active` because the launch path reads that file and
  never parses the config. Files written before this exist and simply yield `ACTIVE_NATIVE=""`;
  `read_active` must initialise it or `set -u` fires
- **It is not `launch_vanilla()`.** That one is still the unconfigured-by-accident path (a
  `[_defaults]` pointing at a keyless provider) and still warns. Native mode is a deliberate choice
  and says so with a normal `info` line. Two `test.sh` sections now force
  `set_key _defaults provider anthropic` to keep reaching the fallback
- **The scrub is deliberate.** A pure passthrough would be marginally more "identical to claude",
  but a leftover `eval "$(ccs env)"` for zai would then silently win. Every `ANTHROPIC_*` /
  `CLAUDE_CODE_*` var ccs manages is `-u`'d, so `ccs use claude` always means the same thing
- `cmd_env` mirrors it: only `unset` lines, no exports. The trailing unconditional
  `export ANTHROPIC_MODEL` moved into the two non-native branches, and the caffeine stderr note
  became `caffeine_env_note()` so both paths share it
- `require_config` appends `[claude]\nnative=true` to any config that declares no `native=` key at
  all. Guarding on the key (not the section name) makes it idempotent and leaves a config that
  already has a native provider alone. It never rewrites an existing `[_defaults]`: an install in
  place keeps the provider it was on, and only new configs default to `claude`
- **Not a third exception to the zero-interference principle**: it writes only to
  `~/.claude-provider/`, never to `~/.claude`

## Key design decisions

- POSIX sh compatible (no bash-isms: no `[[ ]]`, no arrays, no `${var//pattern}`)
- `local` keyword used despite not being strictly POSIX (supported everywhere in practice)
- `env -u` used in `cmd_launch` to scrub conflicting inherited vars (same spirit as `local`: not strictly POSIX, supported by GNU/BSD/macOS/busybox). Native launch unsets third-party vars and vice versa; `cmd_env` native branch unsets the tier vars a third-party eval may have exported
- `config_set` refuses a value containing a newline: one line per key is the file format, and a
  wrapped paste used to be cut at the first newline with the remainder left in the section as a
  stray line — live config if it contained an `=`
- `require_config` checks the section name as well as the `native=` key before appending `[claude]`.
  A config that already had a provider called `claude` (a corporate proxy, a reseller) otherwise
  gained a second one on the first command after upgrading, whose `native=true` won at parse time
  and silently discarded the configured endpoint
- `cmd_status` reports a state file that names no provider instead of exiting non-zero with no
  output: `read_active` accepts a file cut short by a full disk or a Ctrl-C, and `load_state` then
  returns non-zero into a bare call that `set -e` turned into a silent death
- `fmt_tokens` strips leading zeros before any arithmetic — `$(( 0100000 ))` is octal, so a pinned
  `context_tokens=0100000` displayed as 32K
- **`$CCS_SCRUB` is that list, written once.** Both the native launch and `launch_vanilla` claim to
  run claude as claude, so both scrub. `launch_vanilla` used not to, which meant a leftover
  `eval "$(ccs env)"` for another provider silently won: ccs announced "launching vanilla claude"
  while the session went to that provider's endpoint, on that provider's token. One list also
  removes the drift risk between two copies of eleven variable names
- `ccs -h|--help|-v|--version` are intercepted in `main()` BEFORE the generic `-*` claude passthrough — everything else starting with `-` goes to claude
- Unconfigured launch (no active provider + no default api_key) falls back to vanilla `claude` with a warning instead of dying (`launch_vanilla()`)
- `load_state()` is the single place that resolves active state or `[_defaults]`; `cmd_launch`,
  `cmd_env` and `cmd_models` all go through it (return 1 = no default provider, 2 = no api key)
- The two token-limit vars are appended to `exec env` as unquoted words that expand to nothing when
  unknown — safe only because `is_uint` guarantees they are digits-only (`# shellcheck disable=SC2086`)
- Config values stored in `cfg_<section>_<key>` shell variables, built by `cfg_var()`, retrieved via
  `get_cfg()`. **The join is escaped, because it is otherwise ambiguous**: section names and keys
  share the alphabet `[A-Za-z0-9_]`, so `[zai_api] key=` and `[zai] api_key=` both landed in
  `cfg_zai_api_key` and one silently overwrote the other. Every `_` inside a name is doubled, which
  makes the single `_` between them the only odd-length run of underscores at the boundary.
  Hyphens are rejected in section names precisely because shell variable names have no spare
  character, so escaping is the only way out;
  `config_set()` writes one back (awk, creates the section when missing). **Values reach awk
  through `ENVIRON`, never `-v`**: a `-v` assignment gets escape processing, so a value containing
  `\n` was written as a real newline and split the `key=value` line in two, leaving a malformed
  config and a credential truncated at the first backslash. `write_defaults` follows the same rule.
  Section and key stay `-v` — they are regex operands, already restricted by `valid_ident`
- **Sections starting with `_` are reserved** (`[_defaults]`, `[_sync]`): parsed into `cfg_*` like
  any other but never added to `$PROVIDERS`, so they stay out of `ccs list` and `ccs use`. Adding a
  new settings section means picking a `_` name, nothing else
- All writes to `~/.claude/settings.json` go through `settings_prepare` / `settings_attach_hook` /
  `settings_detach_hooks`. Detach is **scoped by event name**, which is what lets `notify` own
  `Stop`/`Notification` and `sync` own `SessionStart`/`SessionEnd` without either clobbering the
  other. Both also share `$HOOKS_DIR`, so neither may `rm -rf` it — only its own scripts, then
  `rmdir` if empty
- All providers must expose an **Anthropic Messages API** compatible endpoint — except a
  `native=true` section, which is not an endpoint at all (see Native login above)
- `anthropic` provider is special: uses `ANTHROPIC_API_KEY`, no `ANTHROPIC_BASE_URL`
- Third-party providers use `ANTHROPIC_AUTH_TOKEN` (not `ANTHROPIC_API_KEY`) to avoid the "Detected a custom API key" interactive prompt
- Section names must be `[a-zA-Z0-9_]` only (no hyphens — invalid in shell variable names)
- Color variables use `$(printf '\033[...]')` to store real escape bytes (not literal strings)
- All `printf` calls pass color variables via `%s`, never in the format string

## File structure

```
ccs                 # Main script — all logic here
config.template     # Default config with all providers
test.sh             # Integration test suite (run in CI, hermetic: stubs llm-models)
.releaserc          # semantic-release config
.version-hook.sh    # Injects version into ccs during release
.github/workflows/  # test.yml — one CI workflow: test.sh + shellcheck (ubuntu + macos),
                    # the real systemd-inhibit job, then semantic-release behind
                    # `needs` so a red suite cannot publish
```

## Commands

`ccs use|list|status|config|launch|with|env|models|notify|caffeine|relaunch|sync|doctor|reset|purge|help|version|completion`

Four short aliases are dispatched too — `ls`, `st`, `cfg`, `run` — and they are part of
`$CCS_COMMANDS`, both completion heredocs and `cmd_help()`. They existed undocumented in all
three for a long time because the test that was supposed to catch exactly that retyped the
command list out of the source instead of deriving it from `main()`; it now reads `main()`'s
own case labels, so an addition that is not documented fails the suite.

`ccs completion bash|zsh` prints a **static** script (heredocs in `completion_bash` /
`completion_zsh`). Commands and subcommands are spelled out from `$CCS_COMMANDS`; provider names
are read from the config file by the script itself with `$CCS_SECTION_SED`, so completing never
runs ccs. That sed excludes `_`-prefixed sections, which are offered only where a section is
expected (`config get|set`). Both scripts skip leading launch flags before reading the command
word. **When a command or subcommand is added, update both heredocs and `$CCS_COMMANDS`** — the
test drives the bash function directly and checks every command word of `main()`.

Plus four launch flags consumed in `main()` before the generic `-*` passthrough: `--caffeine[=mode]`,
`--no-caffeine`, `--relaunch`, `--no-relaunch`.

`ccs with <provider>[/<model>] [args…]` is a one-off launch: `launch_prepare` (sync + caffeine,
shared with `cmd_launch`) then `parse_config` + `validate_provider` + `resolve_provider` +
`launch_resolved` — never `write_active`/`write_defaults`. The split is at the **first** `/` so a
model id with slashes (`openrouter/anthropic/claude-sonnet-4`) survives; everything after the
first word goes to claude untouched. `launch_resolved` is the tail of every launch (native branch
included) and is the only place that execs claude with `ACTIVE_*`.

`ccs config` alone opens `$EDITOR`; `config get <section> <key>` prints one value (empty and exit 0
when unset), `config set <section> <key> [value]` writes one through `config_set` (creating the
section), reading the value from stdin when omitted — with `stty -echo` when stdin is a terminal,
so a key never lands in shell history. Names are validated with the parser's alphabet
(`valid_ident`). A key set this way is live at the next launch because `load_state` re-reads the
config.

## Keep awake (`ccs caffeine`)

- The whole feature is **one command prefix** spliced into the launch's `exec`, between `env` and
  `claude`. `exec` is what makes it correct: the assertion is scoped to the claude process, it is
  released on exit/crash/signal, and claude's exit status still reaches the shell (verified:
  `caffeinate -i sh -c 'exit 3'` → 3). The `exec` itself now lives in `launch_run`, the single
  choke point every launch goes through (see Relaunch below); with relaunch off it is a plain `exec`
- `CAFFEINE_CMD` is spliced **unquoted**, same trick as `$ctx_env $out_env`. That is only safe
  because every word in it is space-free by construction — `--why=ccs-session`, never
  `--why="ccs session"`. Any future flag with a spaced value would silently word-split; put it in
  the `--k=v` form or don't add it
- Resolution happens **before `load_state`** in `cmd_launch`, so `launch_vanilla` is caffeinated
  too: keeping the machine awake is about the machine, not about which model answers
- `caffeine_mode` calls `parse_config` itself. It has to: `load_state` returns early without ever
  parsing the config whenever `~/.claude-provider/active` exists, which would make a configured
  `caffeine=` read as empty. There is a test for exactly this
- **Never fatal, and never silently useless.** No `caffeinate` / `systemd-inhibit` /
  `gnome-session-inhibit`, or an OS ccs doesn't know (Git Bash reports `MINGW64_NT-*`, Cygwin
  `CYGWIN_NT-*`, BSD its own) → `warn` once and launch anyway. Same contract as `llm-models`
- **Present is not permitted, so the wrapper is probed.** It becomes the `exec`ed program, so one
  that exits on a refused lock takes claude down with it — and a headless or container Linux box
  refuses every time, which made `caffeine on` mean "claude never runs". `caffeine_resolve` runs
  `$CAFFEINE_CMD sleep 0` once and drops the wrapper if that fails. `sleep 0` rather than `true`:
  the wrapper execs what it is given and a trimmed PATH may carry no `true` binary, which would
  read as a refusal. Return codes are now three-valued — 0 resolved, 1 nothing installed, 2 the
  branch already explained itself (WSL, or a refusal) — so callers never print a second,
  contradictory warning. `ccs doctor` reuses the same function and so stops reporting `ok` for a
  wrapper that cannot work
- **A refusal mid-wait must not kill a pending relaunch.** `relaunch_wait` falls back to a plain
  `sleep`; under `set -e` the wrapper's non-zero status used to end ccs silently, hours in
- **WSL is special-cased** because it is the one platform that would look like it worked: `uname -s`
  says `Linux` and `systemd-inhibit` may well exist, but a Linux VM has no reach into the Windows
  host's power management, so the host sleeps regardless. Detected via `microsoft` in
  `/proc/sys/kernel/osrelease` (both WSL1 and WSL2 match) → warn, no wrapper. `CCS_OSRELEASE`
  overrides that path **for the test suite only**, so the branch is covered on macOS and ubuntu
  runners alike; nothing else should ever set it
- Native Windows is out of scope: `ccs` is POSIX sh and cannot run there. claudfeine keeps its
  PowerShell wrapper (`SetThreadExecutionState`) for that case
- Two modes because keeping the display lit all night is rarely wanted: `system` (default,
  `caffeinate -ims` / `--what=sleep`) and `display` (`-dims` / `--what=sleep:idle`)
- State is `[_defaults] caffeine=` — a single key, not a new `_` section, since it sits next to
  `auto_context` as another launch-shaping default. Absent key = off, so old configs need no
  migration. With `include_ccs=true` it travels through `sync_merge_ccs_config` like any other
  non-`[_sync]` key, which is intended
- **This is not a third exception to the zero-interference principle**: it writes only to
  `~/.claude-provider/config` and never touches `~/.claude`
- `ccs env` cannot carry it — a sleep assertion is a process, not a variable. It prints a note on
  **stderr** so `eval "$(ccs env)"` keeps a clean stdout
- Ported from [claudfeine](https://github.com/maxgfr/claudfeine), which stays the standalone
  wrapper for people not using ccs. Windows is out of scope here (ccs is POSIX sh)
- `test.sh` stubs the tool under **both** `caffeinate` and `systemd-inhibit` so the same assertions
  run on the macOS and ubuntu runners, and shadows `uname` to reach the WSL, Windows-shell and
  unknown-OS branches. Because every flag is `-x` or `--k=v`, the stub's
  `while case $1 in -*) shift` loop lands exactly on `claude`
- The `gnome-session-inhibit` fallback needs `systemd-inhibit` genuinely absent from `PATH`, so its
  test rebuilds `PATH` from symlinks to the binaries ccs needs — the same trick as
  `[sync: git absent]`. Without it that branch would be code that runs nowhere
- A stub proves the flags ccs passes, not that systemd accepts them, so the **`keepawake` CI job**
  runs the real `systemd-inhibit` on ubuntu and requires the lock to exist while the wrapped
  process is alive (`sleep` without `idle` in system mode, `sleep:idle` in display mode) and to be
  gone afterwards. It probes the runner's own ability to inhibit first, so a runner limitation
  never reads as a ccs pass

## Relaunch after the usage limit (`ccs relaunch`)

- **`launch_run` is the choke point.** The four `exec … claude` sites (vanilla, native, third-party,
  Anthropic) call `launch_run <cmd…>` instead; off means `exec "$@"`, byte-for-byte the old
  behaviour. On, `relaunch_loop` runs the command as a child, and only returns (to the `exec`) when
  a tty is needed and `script(1)` is missing
- **Recordings live in `~/.claude-provider/tmp/`, named `<what>.<pid>`, and every launch sweeps the
  ones whose pid is gone.** A trap cannot be the guarantee: it does not run on `SIGKILL`, and it
  does not run while the shell is still waiting on the recorded pipeline — which is exactly when a
  session gets interrupted. Verified: two files survive a `kill -9` and the next launch removes
  them. A pid that answers "operation not permitted" belongs to another user and is left alone.
  The traps stay as a second line, but the sweep is the one with a test
- **Recording**: on a terminal, `script(1)` gives the TUI a real pty — positional form on
  Darwin/BSD, `-c "<string>"` on util-linux/busybox with `SHELL=/bin/sh` pinned and every word
  through `sh_quote`. On a pipe, stdout and stderr each go through their own `tee` (fd 3/4
  juggling) so `-p` consumers still see them apart. Claude's exit status comes back through a file
  named by `CCS_RELAUNCH_STATUS`, because neither wrapper is trusted to relay it, and the pipe-side
  subshell runs `set +e` or a non-zero claude leaves before writing it. The log is a temp file
  removed right after it is read
- **Detection** (`relaunch_detect`): last line matching `limit.*reset` after stripping CR and ANSI,
  then only the text **after the last "reset"** is parsed — a "3pm" in the conversation must not win.
  `limit.*reset` alone is not enough: "your GitHub API rate limit resets at 3pm" ends a perfectly
  successful session and used to buy a 22-hour wait and a second, unwanted session. The line must
  also carry the shape of a message about the user's own allowance (`hit your … limit`,
  `usage limit`, `limit reached`) and must not be the `approaching` warning, which is mid-session.
  Returns 1 = no limit message (exit with claude's status), 2 = message but no readable time (warn,
  then exit with the status). Clock `H[:MM]am|pm`, optional `Mon D` (weekly wording), optional
  `(Area/City)` zone
- **Date maths** (`relaunch_target`): BSD forms first — `date -r`, `date -j -f` — GNU `-d` second,
  because GNU `-d` on BSD would try to set the kernel DST flag. Seconds are pinned to `:00`: BSD
  `-j` fills any field absent from the format with the current time (found the hard way).
  `env ${tz:+"TZ=$tz"}` because `TZ=""` means UTC, not local. **A past time usually means the
  message was read late, not that the reset is far away**: the recording is always parsed after the
  session ended, so the user quitting after the printed reset is the ordinary case. A dated reset
  in the past now relaunches immediately — the old +1 year turned an hour of lateness into 365 days
  of waiting. A clock-only reset still rolls to tomorrow, since "resets 1am" said at 11pm really is
  tomorrow, but only while the roll lands within `RELAUNCH_STALE_AFTER` (6 h); the window it belongs
  to is a few hours wide, so anything further out is a stale message and relaunches now. `CCS_RELAUNCH_NOW` freezes "now" **for the test suite only**, same
  contract as `CCS_OSRELEASE`
- **Wait** (`relaunch_wait`): 30 s chunks, each one `$CAFFEINE_CMD sleep N` — the wait is exactly
  when the machine must not sleep, so it is wrapped like claude is. Off, ccs warns that the wait
  sleeps with the machine
- **Relaunch args**: `--continue` is inserted right after the first `claude` word by rotating `"$@"`
  (`set -- "$@" "$w"`), skipped when `-c|--continue|-r|--resume` already follows `claude`. The
  original arguments are kept, so a `-p "task"` is re-sent into the continued conversation
- Interactive claude does **not** exit on the limit: the user quits, ccs sees the message in the
  recording. `-p` is fully automatic
- `test.sh` covers the tee path only (no tty on CI): a shim that hits the limit once, both wordings,
  the after-"reset" rule, no duplicate `--continue`, status passthrough, stream separation, and the
  caffeinated wait. The `script(1)` path was checked by hand on macOS by running ccs under an outer
  `script` (the shim saw a tty and `RESUMED:--continue` came back)
- **Not a third exception to the zero-interference principle**: it writes `[_defaults] relaunch=`
  only, never `~/.claude`

## Config sync (`ccs sync`)

- `SYNC_PATHS` at the top of `ccs` is the **allow-list** of what leaves `~/.claude`. It is an
  allow-list on purpose: a real `~/.claude` is gigabytes of `projects/`, `jobs/` and
  `file-history/`. Never invert it into a deny-list
- One engine for both backends, because **a gist is a git repository**. `kind=gist` stores a
  flattened tree (`/` → `%2F`, `%` → `%25`, encode `%` first / decode it last) because GitHub's
  gist UI hides subdirectories; `kind=repo` stores the real tree. `.ccs-sync` records the kind so
  `import` decodes without configuration
- **The manifest carries no timestamp on purpose.** It has to be byte-identical when nothing
  changed, or every push would produce a commit — once per launch under `sync auto on`
- Three transforms make a restored config actually work, all applied to the *staging tree*, never
  by walking `~/.claude`: `tar -ch` dereferences symlinks (`skills/` is routinely links into
  another checkout), `sync_rewrite_home` swaps `$HOME` for `__CCS_HOME__` and back, and
  `sync_strip_ccs_hooks` / `sync_reattach_ccs_hooks` keep machine-local hook paths out of the remote
- **Dereferencing brings the nested `.git` with it.** A skill directory that is a checkout, or a
  link into one, used to be recorded by `git add -A` as a `160000` gitlink holding no file content:
  the push said "Backed up", the remote held nothing, and a restore left the directory empty.
  `sync_copy_tree` drops nested `.git` entries from the copy at `-mindepth 2`, which is what keeps
  ccs's own working copy at `$SYNC_DIR/.git`. Files are the thing being backed up; the nested
  repository's history is not
- **One path may refuse to extract.** `sync_apply`'s additive branch extracts over what is already
  there, and bsdtar will not extract through a directory symlink. Under `set -e` that ended the
  `SYNC_PATHS` loop midway — every later path skipped, hooks never reattached, temp tree leaked —
  so the failure is now reported per path and the loop continues
- `sync_scan_secrets` gates every push (`--force` overrides). In the auto path it returns 3 and the
  launch continues
- **A remote names paths, not just files.** In gist mode `%2F` decodes to `/`, so an entry called
  `..%2F..%2F.bashrc` used to walk out of the staging tree and write there — before `sync import`
  had even asked. `sync_path_is_contained` refuses any decoded name that is absolute or contains a
  `..` component, and `sync_materialize` applies it to every listed file. The unflatten loop also
  tolerates a failing entry instead of abandoning the rest of the restore
- **`git ls-files` must be asked for real names.** `core.quotePath` is on by default, so a path
  with any non-ASCII byte comes back as `"skills/caf\303\251/SKILL.md"`. `cp` then missed a file
  that was really there, the pull dropped it and the next push deleted it from the remote as well.
  Every `ls-files` call passes `-c core.quotePath=false`
- Mirror is the default (`prune=true`); `--additive` / `prune=false` only ever adds. `sync_apply`
  is the **only** function that writes into `~/.claude`, and `sync_backup_claude` always runs first
- `sync_stage` returns 1 (not `die`) when `~/.claude` has nothing to back up, so `sync status`
  works on a fresh machine
- **The budget must not cost files.** `sync_apply` removes an allow-listed path before extracting
  it, so a watchdog `TERM` landing in that window deletes part of `~/.claude` and nothing puts it
  back — on an ordinary launch, reported only as "config sync timed out". `sync_auto_once` touches
  `$SYNC_CRITICAL_FILE` for the duration of the rewrite and `sync_run_bounded` waits rather than
  kills while it exists, up to a ceiling twelve times the budget. A marker left by a run that was
  killed anyway is cleared at the start of the next one
- `sync auto on` runs inside `sync_run_bounded` (background job + `kill -0` watchdog — macOS has no
  `timeout(1)`) and **must never be fatal**: `cmd_launch` calls it before anything provider-related
  and ignores every failure. The watchdog ticks every 0.1 s (`sleep 0.1` is not POSIX but GNU,
  BSD/macOS and busybox take it; a refusal falls back to 1 s), so a 50 ms sync costs the launch
  50 ms, not a full second
- `include_ccs=true` publishes `~/.claude-provider/config` with every `api_key=` blanked and the
  `[_sync]` section stripped. On the way back, `sync_merge_ccs_config` writes an `api_key` only when
  the local one is empty — a pull must never cost a key
- `test.sh` runs the whole sync suite against a `git init --bare` repo over `file://`: no network,
  no real `gh` — the two `gh`-backed inits are covered by a stub that returns a local bare repo, so
  the flags ccs passes (`--private`, and never `--public`) are asserted along with the
  gh-absent and gh-failing branches. Both `--dry-run` previews and the diverged/unreachable remote
  paths are covered the same way. ccs writes its own git identity into the working copy (`sync_git_identity`), which is
  what makes it pass on a CI runner with no global git config

## Doctor (`ccs doctor`)

- **Read-only, no network.** One `doctor_*` function per area, each printing `ok` / `warn` / `fail`
  lines through the three `doctor_ok|warn|fail` helpers; only `doctor_fail` flips `DOCTOR_FAILED`,
  and that is the sole source of the exit status. A missing optional tool is a `warn` that names
  what it switches off — the same contract as the runtime degradation
- Reuses the real helpers rather than re-deriving anything: `have_git`, `have_llm_models`,
  `caffeine_mode` + `caffeine_resolve`, `read_active` + `has_provider`, `load_sync_cfg`, and jq
  for the hook scan (`.hooks[][].hooks[].command` filtered on `$CCS_HOOK_MARKER`, each checked with
  `-x`). Invalid section headers are found with a grep on the file, because `parse_config` only
  reports them on stderr
- `test.sh` covers it with the existing stubs plus a rebuilt bare `PATH` (same trick as
  `[sync: git absent]`) to reach every warn, and a hand-written `settings.json` for the orphan-hook
  and invalid-JSON fails

## Notifications (`ccs notify`)

- `notify on [terminal]` generates three POSIX sh hook scripts (heredocs embedded in `ccs`) into `~/.claude-provider/hooks/`: `notify-emit.sh` (terminal detection + OSC emission), `notify-stop.sh` (Stop hook), `notify-attention.sh` (Notification hook, filters `notification_type`), then jq-merges references into `~/.claude/settings.json`
- `SubagentStop` is deliberately NOT hooked and `agent_completed` notifications are ignored — subagents/background tasks must stay silent
- Terminal methods: ghostty/wezterm → OSC 777, iterm2 → OSC 9, kitty → OSC 99, macos → osascript, bell → BEL only. All also emit a standalone BEL (dock badge/bounce). `auto` (default) detects at hook runtime via `TERM_PROGRAM`/`KITTY_WINDOW_ID`
- Idempotent merge: entries whose command contains `/.claude-provider/hooks/` (`$CCS_HOOK_MARKER`) are replaced, never duplicated; user's other settings are preserved. The merge goes through the shared `settings_*` helpers and touches **only** `Stop` and `Notification`
- `notify off` restores the previous `preferredNotifChannel` (saved in `~/.claude-provider/notify-state` on first install)

## Context window (`ccs models`)

- Claude Code assumes a 200k window for any model it doesn't ship in its own table. `ccs` sets
  `CLAUDE_CODE_MAX_CONTEXT_TOKENS` (and `CLAUDE_CODE_MAX_OUTPUT_TOKENS`) to the model's real limits,
  which both sizes auto-compact and silences the "not a model this version recognizes" warning
- Claude Code only honours `CLAUDE_CODE_MAX_CONTEXT_TOKENS` for model ids that do **not** start with
  `claude-`, so `ccs` sets it in the third-party branch only and `-u`-scrubs it in the native one.
  It is a single global value — sized from the main model, not per tier
- Values are plain integers. `200k` parses as `200`, so `is_uint` rejects anything non-numeric
- Metadata comes from `llm-models` (github.com/maxgfr/llm-models), a `depends_on` in the Homebrew
  formula. The script still degrades gracefully when it is absent (manual installs, broken PATH) →
  no window set, `ccs` behaves exactly as before. Do not make it fatal. `llm_lookup` prefers
  `llm-models resolve --endpoint <base_url> --field …` (>= 1.3, endpoint-scoped so a reseller entry
  can't win) and falls back to `info --json` + awk for older versions
- Answers are cached in `~/.claude-provider/models-cache` (`provider model ctx out epoch id`, one
  line each, 7-day TTL, `-` for unknown fields). A stale entry is still used when a lookup fails.
  `ccs purge` removes it with the rest of the dir; `ccs reset` deliberately does not. An auto pick
  is three lines in the same format, `model` being `auto#opus` / `auto#sonnet` / `auto#haiku` (or
  `auto:<filter>#…`), field 6 the full catalogue id (`zai/glm-5.3`)
- Resolution order in `load_limits`: `auto_context=false` → `context_tokens=`/`max_output_tokens=`
  in the provider section → fresh cache → llm-models → stale cache → unknown (env var not set)
- `test.sh` shadows `llm-models` with a stub on `PATH` for the whole suite (`FAKE_LLM_MODELS` holds
  the `resolve` answer, unset means no match; `FAKE_LLM_LATEST` the `latest` answer, defaulting to
  the tiers zai used to pin so the template's `model=auto` resolves everywhere; `FAKE_LLM_OLD`
  fakes a < 1.4 install; `FAKE_LLM_CALLS` journals every call) so CI never touches the network
- **Do not reach for `modelOverrides` to silence the leftover
  `[claude-code:unrecognized_model]` diagnostic.** Its schema is `Record<string,string>` mapping an
  Anthropic model id to a provider-specific one, so an entry makes Claude Code resolve the model to
  a `claude-*` id — which makes it *ignore* `CLAUDE_CODE_MAX_CONTEXT_TOKENS` and adopt that
  Anthropic model's window instead. It also lives in `~/.claude/settings.json`, off-limits outside
  `ccs notify`. Verified live: the context warning goes away, that one diagnostic line stays

## Automatic model choice (`model=auto`)

- **The spec is persisted, never the pick.** `cmd_use` writes `auto[:filter]` into `active` and
  `[_defaults] model=`; `load_state` hands it back to `resolve_provider` and the pick is made again
  at every launch. Persisting the pick would freeze a snapshot, which is the thing auto exists to
  avoid
- **`resolve_provider` is the single resolver.** Every path that turns a section into `ACTIVE_*`
  (`use`, `with`, `load_state` for launch/env/status/models) goes through it, so nobody else ever
  sees a literal `auto`. `ACTIVE_AUTO` holds the spec when the main model was auto, else empty
- **`latest` replaces `resolve` for the whole tier set.** One subprocess answers opus, sonnet and
  haiku with their windows; `load_limits` short-circuits on the `AUTO_*` slots before the cache
  chain, so the main model never reaches `llm_lookup` and `ccs models` shows the opus/haiku rows
  without a call. The window is the sonnet line's — the main model
- **The API id is the catalogue id minus its first segment** (`${id#*/}`), not its last:
  `openrouter/anthropic/claude-sonnet-5` must launch as `anthropic/claude-sonnet-5`
- **Explicit tiers win.** `opus_model=` / `haiku_model=` in the section override their auto pick;
  the main model is always the sonnet pick
- **Three cache lines per spec, `<spec>#<tier>`**, through the unchanged `cache_lookup` /
  `cache_store`. Freshness is the sonnet line's age against `MODELS_CACHE_AUTO_TTL` (24 h): a model
  choice should follow a release faster than a context window. Opus/haiku fall back on the sonnet
  line. The filter may not contain whitespace — it is a field in a space-split line — so
  `resolve_provider` dies on one. Note that `cache_lookup` passes the key through `awk -v`, which
  does escape processing: fine for `#` and `:`, as it already was for model ids
- **Stale is used with a warning; nothing cached dies.** `resolve_auto_models` never lets a launch
  go out with an empty `ANTHROPIC_MODEL`. The die is explicit because `resolve_provider` runs under
  `||` / `if` where `set -e` is off — same reason as its `|| exit 1`. The two messages name the
  version needed (llm-models >= 1.4) and the manual alternative (`ccs use <p> <model>`)
- **The launch does not probe.** It calls `latest` and treats a failure as "no answer", one
  subprocess. `ccs doctor` alone probes, offline, by grepping `latest` out of the command list of
  `llm-models --help` — **not** `llm-models latest --help`: Commander answers that with the global
  help and exit 0 on 1.3.1, which made doctor report `ok` against the very version it was meant
  to catch. It lives in `doctor_config` because the config has to be parsed first
- **No `base_url` means nothing pinned.** `[anthropic] model=auto` sets `ACTIVE_MODEL=""` with no
  lookup; `launch_resolved` has `-u ANTHROPIC_MODEL` at the head of the Anthropic `env` list and
  passes `${ACTIVE_MODEL:+"ANTHROPIC_MODEL=$ACTIVE_MODEL"}` (the `${tz:+"TZ=$tz"}` idiom), so the
  variable is absent rather than empty; `cmd_env` prints `unset`. The third-party branch never
  sees an empty model: `resolve_auto_models` dies first
- **`cmd_list` reads the cache only.** It walks every provider, and N subprocesses is what the
  launch-path rule forbids: `auto → <pick>`, `auto (not resolved yet)`, or `auto (claude's default)`
- **`AUTO_REFRESH` is set before `load_state`** in `cmd_models refresh`: the resolution runs
  inside `load_state`, so a flag set afterwards would refresh nothing
- **A relaunch reuses the pick.** `relaunch_loop` re-executes the same argv hours later; the model
  resolved at the start is what `--continue` gets, which is also the only thing that makes sense
  mid-conversation
- `auto_context=false` switches the window off, not the pick: `resolve_provider` runs before
  `load_limits` looks at it
- Old `active` files cannot carry `auto` (it did not exist), but a hand-edited one whose provider
  vanished from the config is refused in `load_state`'s legacy branch rather than launched as
  `ANTHROPIC_MODEL=auto`
- Ordering of `ccs use` output: the pick is shown as `auto → <main> (opus <o>, haiku <h>)` by
  `model_label`, shared with `status`, the launch line (`short` form) and `doctor`

## Adding a new provider

1. Add `[provider_name]` section to `config.template` with `base_url`, `api_key`, `model` —
   `model=auto` when llm-models knows the endpoint (check with `llm-models latest --endpoint <url>`),
   an explicit id otherwise. Multi-vendor catalogues stay explicit; `auto:<filter>` is available
2. Add the same section to the inline fallback config in `require_config()` inside `ccs`
   (the two must stay byte-compatible — the inline heredoc is the manual-install path; a test
   diffs them, comments aside)
3. Update README.md providers table
4. The provider **must** support the Anthropic Messages API format

## Release process

Automated via semantic-release on push to `main`, as the last job of the CI workflow:
1. `test` (both runners) and `keepawake` pass — `needs` makes this a gate, not a hope
2. Conventional commit → version bump
3. `.version-hook.sh` injects version into `ccs`
4. GitHub release created
5. `homebrew-tap` daily cron auto-updates the formula SHA256

Releasing used to be its own workflow on the same `push`, which is a race rather than a
stage: 1.8.0 and 1.8.1 both shipped from commits whose test suite was red.

## Conventions

- **Never `A && B || C`.** ShellCheck 0.9/0.10 (what the ubuntu runner ships) report SC2015 there
  and the CI step fails; 0.11 relaxed the heuristic, so a local run can pass while CI does not.
  Write `if ! A || ! B; then C; fi`. To check against the CI version:
  `docker run --rm -v "$PWD:/mnt" koalaman/shellcheck:v0.10.0 -s sh -e SC3043 ccs test.sh`
- The test matrix is `fail-fast` by default: a red shellcheck cancels the macOS job, which then
  reads as "failed" without having run. Check which step actually failed before hunting a
  macOS-specific bug
- **A test that launches for real must leave `caffeine=off`.** The ubuntu runner denies inhibitor
  locks to the `runner` user (no logind session, no polkit — the `keepawake` job says so), so
  `systemd-inhibit … claude` exits non-zero and `set -e` kills the suite. macOS `caffeinate` works,
  so this fails on CI only. Sections that turn caffeine on must turn it back off, or launch with
  `caffeine_shims` on `PATH`

- Conventional commits: `feat:`, `fix:`, `docs:`, `refactor:`
- `printf` instead of `echo -n` (portability)
- `set -eu` for safety
- Colors only when stdout is a terminal
- API keys masked in `ccs status` output

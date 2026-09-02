# CLAUDE.md

**When changing commands, options, or behavior: always update CLAUDE.md, README.md, and `cmd_help()` in `ccs` together. Run `./test.sh` to verify.**

## Project overview

`ccs` (Claude Code Switch) is a minimal POSIX sh script for switching Claude Code between AI providers — including a `[claude]` provider that switches to *nothing*, i.e. claude on its own login — for backing up the `~/.claude` config that makes a good install, and for keeping the machine awake while a session runs. It is a **sidecar tool** — `claude` always works as-is. Provider switching only injects env vars into the child process spawned when running `ccs` (defaults to launch); the two commands that do write to `~/.claude` are listed under Core principle below.

## Core principle

**`claude` must always work on its own.** `ccs` never modifies the user's shell, dotfiles, or Claude Code config. All state lives in `~/.claude-provider/` and env vars only exist inside the `ccs` subprocess (`exec env ... claude`).

**Two exceptions, both opt-in:**

1. `ccs notify on|off` edits `~/.claude/settings.json` (hooks + `preferredNotifChannel`). Backed up to `~/.claude-provider/settings-backup.json`, fully reversed by `notify off`. Requires jq.
2. `ccs sync pull|import` writes into `~/.claude`, restricted to `$SYNC_PATHS`; `ccs sync hooks on` adds `SessionStart`/`SessionEnd` entries to `~/.claude/settings.json`. Every write is preceded by a snapshot into `~/.claude-provider/sync-backup/<timestamp>/`. Requires git.

`purge` detaches both hook families before deleting anything.

## Architecture

- **Single script**: `ccs` (~2500 lines of POSIX sh)
- **Config**: INI format at `~/.claude-provider/config`, parsed with shell builtins (`while read` +
  `case` + parameter expansions). **No `sed`/`cut` in `parse_config`**: it runs on every launch and a
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
  `reset`, removed by `purge`)
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
- `ccs -h|--help|-v|--version` are intercepted in `main()` BEFORE the generic `-*` claude passthrough — everything else starting with `-` goes to claude
- Unconfigured launch (no active provider + no default api_key) falls back to vanilla `claude` with a warning instead of dying (`launch_vanilla()`)
- `load_state()` is the single place that resolves active state or `[_defaults]`; `cmd_launch`,
  `cmd_env` and `cmd_models` all go through it (return 1 = no default provider, 2 = no api key)
- The two token-limit vars are appended to `exec env` as unquoted words that expand to nothing when
  unknown — safe only because `is_uint` guarantees they are digits-only (`# shellcheck disable=SC2086`)
- Config values stored in `cfg_<section>_<key>` shell variables, retrieved via `get_cfg()`;
  `config_set()` writes one back (awk, creates the section when missing)
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
.github/workflows/  # release.yml (semantic-release on push to main)
                    # test.yml (test.sh + shellcheck on PRs, ubuntu + macos)
```

## Commands

`ccs use|list|status|config|launch|with|env|models|notify|caffeine|sync|doctor|reset|purge|help|version`

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

Plus two launch flags consumed in `main()` before the generic `-*` passthrough: `--caffeine[=mode]`
and `--no-caffeine`.

## Keep awake (`ccs caffeine`)

- The whole feature is **one command prefix** spliced into `cmd_launch`'s `exec`, between `env` and
  `claude`. `exec` is what makes it correct: the assertion is scoped to the claude process, it is
  released on exit/crash/signal, and claude's exit status still reaches the shell (verified:
  `caffeinate -i sh -c 'exit 3'` → 3)
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
- `sync_scan_secrets` gates every push (`--force` overrides). In the auto path it returns 3 and the
  launch continues
- Mirror is the default (`prune=true`); `--additive` / `prune=false` only ever adds. `sync_apply`
  is the **only** function that writes into `~/.claude`, and `sync_backup_claude` always runs first
- `sync_stage` returns 1 (not `die`) when `~/.claude` has nothing to back up, so `sync status`
  works on a fresh machine
- `sync auto on` runs inside `sync_run_bounded` (background job + `kill -0` watchdog — macOS has no
  `timeout(1)`) and **must never be fatal**: `cmd_launch` calls it before anything provider-related
  and ignores every failure. The watchdog ticks every 0.1 s (`sleep 0.1` is not POSIX but GNU,
  BSD/macOS and busybox take it; a refusal falls back to 1 s), so a 50 ms sync costs the launch
  50 ms, not a full second
- `include_ccs=true` publishes `~/.claude-provider/config` with every `api_key=` blanked and the
  `[_sync]` section stripped. On the way back, `sync_merge_ccs_config` writes an `api_key` only when
  the local one is empty — a pull must never cost a key
- `test.sh` runs the whole sync suite against a `git init --bare` repo over `file://`: no network,
  no `gh`. ccs writes its own git identity into the working copy (`sync_git_identity`), which is
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
  `ccs purge` removes it with the rest of the dir; `ccs reset` deliberately does not
- Resolution order in `load_limits`: `auto_context=false` → `context_tokens=`/`max_output_tokens=`
  in the provider section → fresh cache → llm-models → stale cache → unknown (env var not set)
- `test.sh` shadows `llm-models` with a stub on `PATH` for the whole suite (`FAKE_LLM_MODELS` holds
  the answer, unset means no match) so CI never touches the network
- **Do not reach for `modelOverrides` to silence the leftover
  `[claude-code:unrecognized_model]` diagnostic.** Its schema is `Record<string,string>` mapping an
  Anthropic model id to a provider-specific one, so an entry makes Claude Code resolve the model to
  a `claude-*` id — which makes it *ignore* `CLAUDE_CODE_MAX_CONTEXT_TOKENS` and adopt that
  Anthropic model's window instead. It also lives in `~/.claude/settings.json`, off-limits outside
  `ccs notify`. Verified live: the context warning goes away, that one diagnostic line stays

## Adding a new provider

1. Add `[provider_name]` section to `config.template` with `base_url`, `api_key`, `model`
2. Add the same section to the inline fallback config in `require_config()` inside `ccs`
   (the two must stay byte-compatible — the inline heredoc is the manual-install path)
3. Update README.md providers table
4. The provider **must** support the Anthropic Messages API format

## Release process

Automated via semantic-release on push to `main`:
1. Conventional commit → version bump
2. `.version-hook.sh` injects version into `ccs`
3. GitHub release created
4. `homebrew-tap` daily cron auto-updates the formula SHA256

## Conventions

- Conventional commits: `feat:`, `fix:`, `docs:`, `refactor:`
- `printf` instead of `echo -n` (portability)
- `set -eu` for safety
- Colors only when stdout is a terminal
- API keys masked in `ccs status` output

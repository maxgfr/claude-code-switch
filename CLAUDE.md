# CLAUDE.md

**When changing commands, options, or behavior: always update CLAUDE.md, README.md, and `cmd_help()` in `ccs` together. Run `./test.sh` to verify.**

## Project overview

`ccs` (Claude Code Switch) is a minimal POSIX sh script for switching Claude Code between AI providers. It is a **sidecar tool** — `claude` always works as-is with zero interference. `ccs` only injects env vars into the child process spawned when running `ccs` (defaults to launch).

## Core principle

**`claude` must always work on its own.** `ccs` never modifies the user's shell, dotfiles, or Claude Code config. All state lives in `~/.claude-provider/` and env vars only exist inside the `ccs` subprocess (`exec env ... claude`).

**Single exception:** `ccs notify on|off` edits `~/.claude/settings.json` (hooks + `preferredNotifChannel`). Explicit opt-in, backed up to `~/.claude-provider/settings-backup.json`, fully reversed by `notify off`; `purge` detaches the hooks first. Requires jq (soft dependency — only the notify command).

## Architecture

- **Single script**: `ccs` (~600 lines of POSIX sh)
- **Config**: INI format at `~/.claude-provider/config`, parsed with shell builtins (`while read` + `case`)
- **State**: `~/.claude-provider/active` stores current provider/model (removed by `ccs reset`)
- **No external dependencies**: no jq, no python, no node
- **Zero footprint**: `ccs reset` or `ccs purge` removes all traces

## Key design decisions

- POSIX sh compatible (no bash-isms: no `[[ ]]`, no arrays, no `${var//pattern}`)
- `local` keyword used despite not being strictly POSIX (supported everywhere in practice)
- `env -u` used in `cmd_launch` to scrub conflicting inherited vars (same spirit as `local`: not strictly POSIX, supported by GNU/BSD/macOS/busybox). Native launch unsets third-party vars and vice versa; `cmd_env` native branch unsets the tier vars a third-party eval may have exported
- `ccs -h|--help|-v|--version` are intercepted in `main()` BEFORE the generic `-*` claude passthrough — everything else starting with `-` goes to claude
- Unconfigured launch (no active provider + no default api_key) falls back to vanilla `claude` with a warning instead of dying (`launch_vanilla()`)
- Config values stored in `cfg_<section>_<key>` shell variables, retrieved via `get_cfg()`
- All providers must expose an **Anthropic Messages API** compatible endpoint
- `anthropic` provider is special: uses `ANTHROPIC_API_KEY`, no `ANTHROPIC_BASE_URL`
- Third-party providers use `ANTHROPIC_AUTH_TOKEN` (not `ANTHROPIC_API_KEY`) to avoid the "Detected a custom API key" interactive prompt
- Section names must be `[a-zA-Z0-9_]` only (no hyphens — invalid in shell variable names)
- Color variables use `$(printf '\033[...]')` to store real escape bytes (not literal strings)
- All `printf` calls pass color variables via `%s`, never in the format string

## File structure

```
ccs                 # Main script — all logic here
config.template     # Default config with all providers
test.sh             # Integration test suite (run in CI)
.releaserc          # semantic-release config
.version-hook.sh    # Injects version into ccs during release
.github/workflows/  # release.yml (semantic-release on push to main)
                    # test.yml (test.sh + shellcheck on PRs, ubuntu + macos)
```

## Commands

`ccs use|list|status|config|launch|env|notify|reset|purge|help|version`

## Notifications (`ccs notify`)

- `notify on [terminal]` generates three POSIX sh hook scripts (heredocs embedded in `ccs`) into `~/.claude-provider/hooks/`: `notify-emit.sh` (terminal detection + OSC emission), `notify-stop.sh` (Stop hook), `notify-attention.sh` (Notification hook, filters `notification_type`), then jq-merges references into `~/.claude/settings.json`
- `SubagentStop` is deliberately NOT hooked and `agent_completed` notifications are ignored — subagents/background tasks must stay silent
- Terminal methods: ghostty/wezterm → OSC 777, iterm2 → OSC 9, kitty → OSC 99, macos → osascript, bell → BEL only. All also emit a standalone BEL (dock badge/bounce). `auto` (default) detects at hook runtime via `TERM_PROGRAM`/`KITTY_WINDOW_ID`
- Idempotent merge: entries whose command contains `/.claude-provider/hooks/` are replaced, never duplicated; user's other settings are preserved
- `notify off` restores the previous `preferredNotifChannel` (saved in `~/.claude-provider/notify-state` on first install)

## Adding a new provider

1. Add `[provider_name]` section to `config.template` with `base_url`, `api_key`, `model`
2. Add the same section to the inline fallback config in `require_config()` inside `ccs`
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

# CLAUDE.md

**Keep this file and README.md in sync with any code change.**

## Project overview

`ccs` (Claude Code Switch) is a minimal POSIX sh script for switching Claude Code between AI providers. It is a **sidecar tool** — `claude` always works as-is with zero interference. `ccs` only injects env vars into the child process spawned by `ccs launch`.

## Core principle

**`claude` must always work on its own.** `ccs` never modifies the user's shell, dotfiles, or Claude Code config. All state lives in `~/.claude-provider/` and env vars only exist inside the `ccs launch` subprocess (`exec env ... claude`).

## Architecture

- **Single script**: `ccs` (~600 lines of POSIX sh)
- **Config**: INI format at `~/.claude-provider/config`, parsed with shell builtins (`while read` + `case`)
- **State**: `~/.claude-provider/active` stores current provider/model (removed by `ccs reset`)
- **No external dependencies**: no jq, no python, no node
- **Zero footprint**: `ccs reset` or `ccs purge` removes all traces

## Key design decisions

- POSIX sh compatible (no bash-isms: no `[[ ]]`, no arrays, no `${var//pattern}`)
- `local` keyword used despite not being strictly POSIX (supported everywhere in practice)
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
.releaserc          # semantic-release config
.version-hook.sh    # Injects version into ccs during release
.github/workflows/  # release.yml (semantic-release on push to main)
```

## Commands

`ccs use|list|status|config|default|launch|env|reset|purge|help|version`

## Adding a new provider

1. Add `[provider_name]` section to `config.template` with `base_url`, `api_key`, `models`, `default_model`
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

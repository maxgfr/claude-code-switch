# CLAUDE.md

## Project overview

`ccs` (Claude Code Switch) is a minimal POSIX sh script for switching Claude Code between AI providers. It manages environment variables (`ANTHROPIC_BASE_URL`, `ANTHROPIC_API_KEY`, `ANTHROPIC_MODEL`, etc.) and persists state in `~/.claude-provider/`.

## Architecture

- **Single script**: `ccs` (~550 lines of POSIX sh)
- **Config**: INI format at `~/.claude-provider/config`, parsed with shell builtins (`while read` + `case`)
- **State**: `~/.claude-provider/active` stores current provider/model
- **No external dependencies**: no jq, no python, no node

## Key design decisions

- POSIX sh compatible (no bash-isms: no `[[ ]]`, no arrays, no `${var//pattern}`)
- `local` keyword used despite not being strictly POSIX (supported everywhere in practice)
- Config values stored in `cfg_<section>_<key>` shell variables, retrieved via `get_cfg()`
- All providers must expose an **Anthropic Messages API** compatible endpoint
- `anthropic` provider is special: `ANTHROPIC_BASE_URL` is **unset** (not empty)

## File structure

```
ccs                 # Main script — all logic here
config.template     # Default config with all providers
.releaserc          # semantic-release config
.version-hook.sh    # Injects version into ccs during release
.github/workflows/  # release.yml (semantic-release on push to main)
```

## Commands

`ccs use|list|status|config|default|launch|env|help|version`

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

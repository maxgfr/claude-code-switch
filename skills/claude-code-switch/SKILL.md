---
name: claude-code-switch
description: Drive claude-code-switch (`ccs`) — switch Claude Code between providers (native login, Anthropic API, OpenRouter, DeepSeek, Z.AI, Kimi, Qwen, MiniMax, any Anthropic-compatible endpoint) and models, apply reversible settings packs (privacy, no-trace, guard, quiet, autonomous), back up and sync ~/.claude to a gist or private repo, keep the machine awake, relaunch after the usage limit, and diagnose the install. Use when the user mentions ccs or claude-code-switch, wants another provider or model for Claude Code, wants less telemetry or no Claude attribution in commits and PRs, wants secrets guarded under bypassPermissions, wants their Claude Code config on another machine, or wants a long run to survive sleep and usage limits.
license: MIT
metadata:
  author: maxgfr
---

# claude-code-switch (`ccs`)

`ccs` is a POSIX sh sidecar. `claude` keeps working on its own; switching a
provider only injects env vars into the claude that `ccs` starts. Its state is
`~/.claude-provider/`. Only `ccs notify`, `ccs pack` and `ccs sync` write to
`~/.claude`, each with a backup first and an exact way back.

`ccs help` is the full, version-exact reference — read it rather than guessing
a flag. Not installed? `brew install maxgfr/tap/claude-code-switch`.

## Look before changing anything

All read-only, no network, safe to run any time:

```sh
ccs status          # provider, model, context window, caffeine, relaunch (key masked)
ccs doctor          # ok / warn / fail per check; exit 1 only when something is broken
ccs pack            # every pack: on, off or partial
ccs pack status guard
ccs list            # configured providers
ccs models          # the context window each model tier resolves to
ccs sync status     # remote, last sync, what a push would send
```

## Never block the session you are in

- **Bare `ccs`, `ccs launch` and `ccs with <provider>` start an interactive
  claude.** From inside an agent session, run a one-off headless instead:
  `ccs with deepseek -p "review this diff"` (nothing saved), or let the user
  launch it.
- **`ccs config` alone opens `$EDITOR`.** Use `ccs config get <section> <key>`
  and `ccs config set <section> <key> <value>`.
- `ccs sync import` needs `--yes` when stdin is not a terminal — and the user's
  explicit go-ahead, see below.

## API keys

- Never put a key in a command line (shell history, process list) and never
  print one. `ccs status` already masks it.
- Best: ask the user to run `ccs config set zai api_key` in their own
  terminal — with no value it reads the key from a hidden prompt.
- Already in an env var? `printf '%s' "$ZAI_API_KEY" | ccs config set zai api_key`.
- Do not `cat ~/.claude-provider/config`: it holds every key. `config get` the
  one non-secret value you need.

## Providers and billing

- `[claude]` (`native=true`) is the user's Claude subscription: nothing injected,
  identical to running `claude`. It is the default.
- `[anthropic]` is the Anthropic **API key, billed per token** — Claude Code
  prefers `ANTHROPIC_API_KEY` over the login whenever it is set. Never switch a
  subscription user onto it, or off it, without asking.
- `ccs use <provider> [model|auto]` saves a default; `ccs with <provider>[/<model>]`
  is one launch, nothing saved. `model=auto` lets llm-models pick the newest
  flagship per tier.
- A new endpoint is a config section (`[A-Za-z0-9_]`, no hyphen) with `base_url`,
  `api_key`, `model` — it must speak the Anthropic Messages API:
  `ccs config set myproxy base_url https://llm.example.com/anthropic`, then the
  key as above, then `ccs use myproxy <model>`.

## Settings packs

`ccs pack on <pack>... | all`, `ccs pack off <pack>`. Previous values are
recorded first; `off` restores them, except values changed since. Settings
apply to claude sessions started afterwards, not the current one.

| Pack | Effect |
|------|--------|
| `privacy` | No telemetry, error reports, `/bug`, feedback survey or drafts, Remote Control, session mirroring, mobile push. Auto-updater stays on |
| `no-trace` | No Claude attribution in commits or PRs, plus a hook refusing to publish one (git, gh, glab, MCP tools) |
| `guard` | Read/Edit deny credential stores and `.env`; a Bash hook refuses secret reads, force pushes, `rm -r` on `/` or `~`, `curl \| sh`, unsigned commits — in `bypassPermissions` too |
| `quiet` | No spinner tips, prompt or plugin suggestions |
| `autonomous` | Continue after the usage limit, a question left 10 min goes on; turns `guard` on |

- `autonomous` changes how the user's sessions behave — confirm before turning
  it on. `pack off guard` is refused while `autonomous` is on.
- Do not hand-edit a key a pack owns in `~/.claude/settings.json`; `ccs doctor`
  reports the drift, `ccs pack on <pack>` re-applies, `ccs pack off` reverts.
- Whether chats train Claude is an account setting, not a pack:
  https://claude.ai/settings/data-privacy-controls

### When a pack refuses you

- `ccs guard: blocked — …` is the user's guard rail. Do not rephrase the command
  to slip past it. Use the safe form it names (`--force-with-lease`), or stop
  and ask the user to run it themselves.
- `ccs no-trace: blocked — …` means the text carries a Claude attribution.
  Remove it — trailer, footer, session link — and retry.

## Sync (`ccs sync`)

An allow-list of `~/.claude` (CLAUDE.md, settings.json, agents, commands,
skills, output-styles, hooks, plugin manifests) to a gist or private repo.
Transcripts, history and credentials never leave; a secret scan gates every push.

- **Ask first**, these publish or overwrite: `sync init --gist-new` /
  `--repo-new <name>` (creates a GitHub resource — prefer a private repo),
  `sync push`, `sync pull` (mirror rewrite of `~/.claude`), `sync import`.
- Preview with `ccs sync push --dry-run` and `ccs sync pull --dry-run`. Every
  restore snapshots `~/.claude` into `~/.claude-provider/sync-backup/` first.
- `ccs sync auto on` syncs on each `ccs` launch and only rewrites `~/.claude`
  when another machine pushed. `ccs sync hooks on` runs a full pull at every
  session start — heavier, prefer `auto`.

## Long runs

- `ccs caffeine on` — the machine stays awake exactly while claude runs.
  `--caffeine` for one launch.
- `ccs relaunch on` — when a session ends on the usage limit, wait for the
  reset, then `claude --continue` with the same arguments. `-p` is fully
  automatic.
- Both apply only to sessions launched through `ccs`, never to a bare `claude`.

## Undo

- `ccs reset` clears the active provider (back to plain `claude`).
- `ccs pack off all`, `ccs notify off`, `ccs sync hooks off`, `ccs sync off`.
- `ccs purge` deletes `~/.claude-provider/` — keys, sync state, snapshots. Never
  without the user asking. It keeps pack settings in `settings.json`; run
  `ccs pack off all` first to revert those.

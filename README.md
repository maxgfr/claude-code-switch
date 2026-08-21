# claude-code-switch

Minimal, zero-dependency provider switching for [Claude Code](https://docs.anthropic.com/en/docs/claude-code). One shell script to rule them all.

Switch between AI providers (Anthropic, OpenRouter, DeepSeek, Z.AI, Kimi, Qwen, MiniMax, Doubao, or any custom endpoint) with a single command, and get each model's **real context window** instead of Claude Code's 200k guess. **`claude` always works as-is** — `ccs` is a sidecar that only injects env vars when you explicitly run `ccs`.

Inspired by [foreveryh/claude-code-switch](https://github.com/foreveryh/claude-code-switch), stripped down to the essentials: **switch provider, set model, launch claude**.

## Features

- **9 built-in providers**: Anthropic, OpenRouter, DeepSeek, Z.AI, Kimi, Qwen, MiniMax, Doubao, Custom
- **Default model**: configurable globally and per provider
- **Right-sized context window**: detects each model's real window so auto-compact stops assuming 200k
- **Config backup & sync**: push `~/.claude` to a gist or private repo, restore it on any machine
- **Tiny footprint**: pure POSIX sh — no python, no node; Homebrew pulls `jq` and `llm-models` for you
- **Zero interference**: `claude` always works normally — `ccs` never touches your shell or Claude config
- **Direct launch**: `ccs` starts Claude Code with the right env vars (scoped to that process)
- **Shell integration** (optional): `eval "$(ccs env)"` exports vars to your current session
- **API key validation**: clear errors when a provider is not configured
- **Masked secrets**: `ccs status` never leaks your full API key

## Installation

### Homebrew (recommended)

```sh
brew install maxgfr/tap/claude-code-switch
```

That also installs [`llm-models`](https://github.com/maxgfr/llm-models) (context-window sizing) and
`jq` (notifications).

### Manual

```sh
# Download the script
curl -fsSL https://raw.githubusercontent.com/maxgfr/claude-code-switch/main/ccs -o /usr/local/bin/ccs
chmod +x /usr/local/bin/ccs

# First run creates ~/.claude-provider/config — add your API keys
ccs config
```

This path skips the dependencies Homebrew would have installed. `ccs` runs fine without them, but
add [`llm-models`](https://github.com/maxgfr/llm-models) for context-window sizing and `jq` for
`ccs notify` when you want those.

`ccs sync` additionally needs `git` (and `gh`, only to create a gist or repo for you). Everything
else works without them.

## Quick start

```sh
# 1. Add your API keys
ccs config

# 2. Switch to a provider
ccs use openrouter

# 3. Launch Claude Code
ccs
```

```
>>> Launching claude with zai / glm-5.3 (1.0M context)
```

## Usage

```
ccs [args...]               Launch claude with active provider (default)
ccs <command> [arguments]

COMMANDS
    use <provider> [model]      Switch to a provider (saves as default)
    list                        List configured providers
    status                      Show active provider and model
    config                      Open config file in $EDITOR
    launch [args...]            Launch claude with active provider env vars
    env                         Print export statements for current shell
    models [refresh|clear]      Show / refresh the context windows ccs will use
    notify on|off|status|test   Desktop notifications when Claude needs you
    sync <subcommand>           Back up ~/.claude to a gist or repo
    reset                       Clear active provider (back to vanilla claude)
    purge                       Remove all ccs data (~/.claude-provider/)
    help                        Show help
    version                     Show version

SYNC SUBCOMMANDS
    sync init --gist-new        Create a secret gist and use it (needs gh)
    sync init --repo-new <name> Create a private repo and use it (needs gh)
    sync init --gist <id|url>   Use a gist you already have
    sync init --repo <url>      Use a repo you already have
    sync push [--force]         Back up ~/.claude to the remote
    sync pull [--additive]      Restore ~/.claude from the remote
    sync import <id|url>        Import someone else's config (asks first)
    sync status                 Remote, scope, last sync, what would push
    sync auto on|off            Sync on every 'ccs' launch (default: off)
    sync hooks on|off           Sync on Claude Code session start/end
    sync off                    Forget the remote, touch no files
```

### Examples

```sh
# Switch provider
ccs use anthropic                     # Use default model (claude-sonnet-5)
ccs use anthropic claude-opus-4-6     # Override model
ccs use openrouter openai/gpt-4o     # OpenRouter with specific model
ccs use deepseek deepseek-reasoner   # DeepSeek R1
ccs use zai glm-5.1                  # Z.AI GLM-5.1
ccs use kimi                         # Kimi K2.5
ccs use qwen                         # Qwen 3.5 Plus
ccs use minimax                      # MiniMax M2.7
ccs use doubao                       # Doubao Seed Code (ByteDance)

# Check state
ccs list                              # See all providers and their status
ccs status                            # See active provider, model, masked API key
ccs models                            # See the context window ccs will use, per tier

# Launch Claude Code
ccs                                   # Launch with active provider
ccs --print "hello world"             # Pass flags through to claude

# Export to current shell
eval "$(ccs env)"                     # Export env vars to current session
```

## Providers

All providers expose an Anthropic-compatible Messages API endpoint, confirmed working with Claude Code.

| Provider     | Base URL                                                  | Default Model                    |
|--------------|-----------------------------------------------------------|----------------------------------|
| `anthropic`  | *(native — no override)*                                  | `claude-sonnet-5`              |
| `openrouter` | `https://openrouter.ai/api`                               | `anthropic/claude-sonnet-4`      |
| `deepseek`   | `https://api.deepseek.com/anthropic`                      | `deepseek-chat`                  |
| `zai`        | `https://api.z.ai/api/anthropic`                          | `glm-5.1`                        |
| `kimi`       | `https://api.moonshot.ai/anthropic`                       | `kimi-k2.5`                      |
| `qwen`       | `https://dashscope-intl.aliyuncs.com/apps/anthropic`      | `qwen3.5-plus`                   |
| `minimax`    | `https://api.minimax.io/anthropic`                        | `MiniMax-M2.7`                   |
| `doubao`     | `https://ark.cn-beijing.volces.com/api/coding`            | `doubao-seed-code-preview-latest`|
| `custom`     | *(user-defined)*                                          | *(user-defined)*                 |

### Z.AI Coding Plan

[Z.AI](https://z.ai) offers a **Coding Plan** optimized for AI-powered coding tools like Claude Code:

- **Models**: GLM-5.1, GLM-5, GLM-4.7, GLM-4.6
- **Plans**: Coding Lite ($6/mo), Standard ($10/mo), Pro ($30/mo)
- **Get your API key**: [z.ai/manage-apikey](https://z.ai/manage-apikey/apikey-list)

```sh
ccs use zai glm-5.1
ccs
```

### Doubao (ByteDance/Volcengine)

[Doubao](https://www.volcengine.com/product/doubao) is ByteDance's AI platform with coding-optimized models:

- **Models**: `doubao-seed-code-preview-latest` (256K context)
- **Free tier**: 50M tokens/day for new users
- **Get your API key**: [Volcengine ARK Console](https://console.volcengine.com/ark)

```sh
ccs use doubao
ccs
```

## Configuration

Located at `~/.claude-provider/config`. Simple INI format, editable by hand:

```ini
[_defaults]
provider=anthropic
model=claude-sonnet-5

[anthropic]
base_url=
api_key=sk-ant-your-key-here
model=claude-sonnet-5

[openrouter]
base_url=https://openrouter.ai/api
api_key=sk-or-v1-your-key-here
model=anthropic/claude-sonnet-4

[zai]
base_url=https://api.z.ai/api/anthropic
api_key=your-zai-key-here
model=glm-5.1
opus_model=glm-5.1
haiku_model=glm-4.7
```

- **`[_defaults]`** — global default provider and model
- **`api_key=`** — empty means not configured
- **`base_url=`** — empty for `[anthropic]` uses native Anthropic API (no `ANTHROPIC_BASE_URL`)
- **`model=`** — main model (maps to sonnet/default tier in `/models`)
- **`opus_model=`** — optional, for `/models` opus tier (falls back to `model`)
- **`haiku_model=`** — optional, for `/models` haiku tier + fast tasks (falls back to `model`)
- **`context_tokens=`** — optional, pins the context window (plain integer; empty means auto)
- **`max_output_tokens=`** — optional, pins the output limit (plain integer; empty means auto)
- **`auto_context=`** — in `[_defaults]`, set to `false` to disable the automatic lookup

Sections whose name starts with `_` are **reserved**: they hold settings, never providers, so they
never show up in `ccs list`. Alongside `[_defaults]` there is `[_sync]`, normally written by
`ccs sync init`:

```ini
[_sync]
remote=https://gist.github.com/<id>.git
kind=gist            # gist | repo
include_ccs=false    # also back up this file, with every api_key= blanked
auto_launch=false    # sync on every `ccs` launch
auto_hooks=false     # written by `ccs sync hooks on|off`
prune=true           # a pull mirrors the remote; false only ever adds
```

Values run to the end of the line, so no trailing comments.

## Context window

Claude Code assumes a **200k** context window for any model it doesn't ship in its own table, so on
a 1M model auto-compact fires four times too early — and it says so on every launch:

```
"glm-5.3" is not a model this version of Claude Code recognizes, so auto-compact
will keep this session within 200k tokens (the context window it assumes)...
```

`ccs` looks the model up and sets `CLAUDE_CODE_MAX_CONTEXT_TOKENS` to its real window, which both
sizes auto-compact correctly and removes the warning:

```
>>> Launching claude with zai / glm-5.3 (1.0M context)
```

Inspect what it will use, per tier:

```sh
ccs models           # context + output limit + where each number came from
ccs models refresh   # re-resolve, ignoring the cache
ccs models clear     # drop the cache
```

```
  Tier     Model         Context   Output    Source         Resolved as
  main     glm-5.3       1.0M      131K      llm-models     zai-coding-plan/glm-5.3
  haiku    glm-4.7       204K      131K      cache          zai/glm-4.7
```

The lookup uses [**llm-models**](https://github.com/maxgfr/llm-models), which Homebrew installs
alongside `ccs`. If you installed `ccs` by hand instead, add it:

```sh
brew install maxgfr/tap/llm-models
```

`ccs` still runs without it — you just get no window, exactly as before — so a broken or missing
install degrades rather than breaks. Answers are cached in `~/.claude-provider/models-cache` for 7
days, so the launch path stays free of subprocesses, and a stale entry is still used when the lookup
fails (offline, say).

Because the same model id is published by many providers with different limits, the lookup is scoped
by the provider's `base_url` — `api.z.ai` resolves to Z.AI's own numbers, not a reseller's.

Override or opt out from the config:

```ini
[zai]
context_tokens=200000       # pin the window (plain integer — "200k" is not valid)
max_output_tokens=131072    # pin the output limit

[_defaults]
auto_context=false          # disable the lookup entirely
```

### Known limits

- `CLAUDE_CODE_MAX_CONTEXT_TOKENS` is a **single global value**, so it is sized from the *main*
  model even when the opus/haiku tiers have different windows. `ccs models` shows all four.
- Claude Code ignores it for model ids starting with `claude-`, which is why `ccs` sets it for
  third-party providers only and scrubs it for native Anthropic.
- It takes a **plain integer**. `200k` parses as `200`, so `ccs` rejects any non-numeric pin with a
  warning rather than passing it through.
- One line survives: Claude Code still emits the diagnostic
  `[claude-code:unrecognized_model] {"model":"glm-5.3",...}`. That one is only silenced by mapping
  the id in the `modelOverrides` setting — which would make Claude Code resolve your model to an
  Anthropic one and *ignore the window you just set*. `ccs` deliberately does not do that, and does
  not write to `~/.claude/settings.json` outside `ccs notify`.
- A model missing from the catalogue (Doubao/Volcengine, for instance) simply gets no window, and
  `ccs` behaves as it did before. Pin it with `context_tokens=`.

## Desktop notifications

Get a desktop notification + dock badge when Claude Code **finishes a task** or **asks you something** — and stay silent for subagents and background tasks (no more notification spam from parallel workflows).

```sh
ccs notify on           # Auto-detect terminal, install hooks
ccs notify on iterm2    # Or pin: ghostty | iterm2 | wezterm | kitty | macos | bell
ccs notify test         # Fire a test notification
ccs notify status       # Show current state
ccs notify off          # Remove everything, restore previous settings
```

**Requires [jq](https://jqlang.org)** (`brew install jq`) — only for this command, the rest of `ccs` stays zero-dependency.

| Terminal | Notification | Dock badge on bell |
|--------------|--------------------------|---------------------|
| Ghostty | OSC 777 | ✅ (`bell-features = attention`) |
| WezTerm | OSC 777 | bounce (configurable) |
| iTerm2 | OSC 9 | ✅ bounce |
| kitty | OSC 99 | configurable |
| Terminal.app | `osascript` | ✅ |
| anything else| bell only | terminal-dependent |

How it works:

- A `Stop` hook notifies when the main conversation turn ends. Subagents fire `SubagentStop`, which is deliberately **not** hooked — they never notify.
- A `Notification` hook notifies only when Claude needs *you* (`permission_prompt`, `agent_needs_input`, `elicitation_dialog`, `idle_prompt`) and ignores `agent_completed`, which fires for every background task.
- The badge only shows while the terminal is unfocused, and clears when you come back.

> **Note:** `ccs notify on` is one of the two exceptions to the zero-interference principle (the other is `ccs sync`): it edits `~/.claude/settings.json` (hooks + `preferredNotifChannel`). It is explicit opt-in, backs up your settings to `~/.claude-provider/settings-backup.json`, and `ccs notify off` restores the previous state. Hook scripts live in `~/.claude-provider/hooks/`.

## Config backup & sync

Reinstalling Claude Code means rebuilding your global `CLAUDE.md`, your settings, your skills and
your commands by hand. `ccs sync` backs up **the part of `~/.claude` that makes a good install** to
a GitHub gist or a private repo, and puts it back on any other machine.

```sh
ccs sync init --gist-new       # create a secret gist (or --repo-new <name>)
ccs sync push                  # back up ~/.claude
ccs sync status                # remote, scope, last sync, what would push

# on the new machine
ccs sync init --gist <id>
ccs sync pull                  # restore

# somebody else's setup, without adopting their remote
ccs sync import <gist-url>
```

### What is backed up

An **allow-list**, never a deny-list — a lived-in `~/.claude` runs to gigabytes of transcripts and
job state, none of which helps you reinstall:

| Backed up | Never leaves the machine |
|-----------|--------------------------|
| `CLAUDE.md` | `projects/`, `jobs/`, `transcripts/`, `plans/` |
| `settings.json` | `history.jsonl`, `shell-snapshots/`, `file-history/` |
| `agents/`, `commands/`, `skills/`, `output-styles/`, `hooks/` | `.credentials.json`, `~/.claude.json` |
| `plugins/installed_plugins.json`, `plugins/known_marketplaces.json` | `settings.local.json`, every cache |

Three things happen on the way out, so the config actually works when it lands:

- **Symlinks are dereferenced.** A `skills/` directory full of links into another checkout is
  copied by content — otherwise the other machine gets dangling links.
- **`$HOME` is replaced by a placeholder** in every text file, and restored on pull. A `statusLine`
  command or a hook path survives a move to a machine with a different home directory.
- **ccs's own hook entries are stripped** from `settings.json` and re-attached from local state on
  pull, so you never inherit hooks pointing at scripts your machine does not have.

A **secret scan** runs before every push and refuses to publish anything shaped like a credential
(`sk-ant-…`, `ghp_…`, AWS keys, private key blocks, an `apiKey` field). `--force` overrides it.

### Gist or repo

Both are git remotes, so it is one engine. The difference is cosmetic: GitHub's gist UI hides
subdirectories, so a gist stores a flat tree with `/` percent-encoded
(`skills%2Fmy-skill%2FSKILL.md`) and a repo stores the real one. `ccs sync pull` and
`ccs sync import` rebuild the tree either way.

`git` is required. `gh` only for `--gist-new` / `--repo-new` — otherwise pass a URL you already
have. Pushing uses your existing git credentials (SSH key or the `gh` credential helper).

### Restoring, and what a pull can cost you

A pull **mirrors** the remote: a file deleted there is deleted here. `--additive` (or
`prune=false`) only ever adds. Either way `~/.claude` is snapshotted into
`~/.claude-provider/sync-backup/<timestamp>/` before a single byte is written, and
`ccs sync pull --dry-run` shows the change first.

### Automatic sync

**Manual by default.** Two opt-in triggers:

```sh
ccs sync auto on      # sync at the start of every `ccs` launch
ccs sync hooks on     # sync on Claude Code session start / end
```

`auto on` gets a five-second budget and can never stop Claude Code from starting: an unreachable
remote, a conflicting history or a detected secret produces a warning and the launch continues.
`hooks on` installs `SessionStart`/`SessionEnd` hooks alongside the notification ones — the two
families are independent, so `ccs notify off` does not unhook sync.

### Syncing the ccs config too

Off by default. Turn it on to carry your providers, models and context pins across machines:

```ini
[_sync]
include_ccs=true
```

Every `api_key=` is blanked before the file leaves the machine, and the `[_sync]` section itself is
stripped so nobody importing your config ends up pointing at your remote. On the way back in, a key
is only ever written when the local one is empty — **a pull can never cost you an API key**.

> **Note:** `ccs sync` is the second exception to the zero-interference principle: `pull` and
> `import` write into `~/.claude`. Both are explicit commands, both snapshot first, and nothing
> outside the allow-list above is ever read or written. `ccs sync off` forgets the remote and
> leaves every file alone.

## Shell integration

Add to `~/.zshrc` or `~/.bashrc` so `ccs use` automatically exports env vars to your current shell:

```sh
ccs() {
    if [ "${1:-}" = "use" ]; then
        command ccs "$@" && eval "$(command ccs env)"
    else
        command ccs "$@"
    fi
}
```

## How it works

`ccs` runs `exec env ... claude` — the env vars only exist in that child process. Your shell and `claude` are never affected.

```
claude          → normal Claude Code, no ccs involvement
ccs             → Claude Code with provider env vars (scoped to that process)
```

`ccs` also **scrubs conflicting inherited vars** (`env -u`) before launching: a stale `ANTHROPIC_BASE_URL` or tier model left in your shell by a previous `eval "$(ccs env)"` for another provider can't leak into the launch. Likewise, `eval "$(ccs env)"` for native Anthropic unsets the third-party tier vars it may have exported before.

If **no provider is configured at all** (no active provider, no API key in the defaults), `ccs` warns and launches vanilla `claude` instead of failing.

| Variable                      | When                                                 |
|-------------------------------|------------------------------------------------------|
| `ANTHROPIC_BASE_URL`            | Third-party providers only (unset for native)      |
| `ANTHROPIC_AUTH_TOKEN`          | Third-party providers only (avoids API key prompt) |
| `ANTHROPIC_API_KEY`             | Native Anthropic only                              |
| `ANTHROPIC_MODEL`               | Always                                             |
| `ANTHROPIC_DEFAULT_OPUS_MODEL`  | Third-party — maps to `opus_model` in config       |
| `ANTHROPIC_DEFAULT_SONNET_MODEL`| Third-party — maps to `model` in config            |
| `ANTHROPIC_DEFAULT_HAIKU_MODEL` | Third-party — maps to `haiku_model` in config      |
| `CLAUDE_CODE_SUBAGENT_MODEL`    | Third-party — uses `model`                         |
| `ANTHROPIC_SMALL_FAST_MODEL`    | Third-party — uses `haiku_model`                   |
| `CLAUDE_CODE_MAX_CONTEXT_TOKENS`| Third-party — the model's real context window      |
| `CLAUDE_CODE_MAX_OUTPUT_TOKENS` | Third-party — the model's real output limit        |

State is persisted in `~/.claude-provider/active` so `ccs` works across shell sessions. Run `ccs reset` to clear it, or `ccs purge` to remove all ccs data.

Everything ccs owns lives in `~/.claude-provider/`: `config`, `active`, `models-cache`,
`hooks/` (notify + sync), `sync/` (the git working copy) and `sync-backup/` (the snapshots taken
before a restore). `ccs reset` only clears `active`; `ccs purge` removes the lot.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[MIT](LICENSE)

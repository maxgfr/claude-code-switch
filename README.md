# claude-code-switch

Minimal provider switching for [Claude Code](https://docs.anthropic.com/en/docs/claude-code). One POSIX shell script to rule them all — no python, no node.

Switch between AI providers (Anthropic, OpenRouter, DeepSeek, Z.AI, Kimi, Qwen, MiniMax, Doubao, or any custom endpoint) with a single command, get each model's **real context window** instead of Claude Code's 200k guess, and keep the `~/.claude` config that makes a good install backed up on a gist or a private repo. **`claude` always works as-is** — running it never goes through `ccs`, and switching provider only injects env vars into the process `ccs` spawns.

Inspired by [foreveryh/claude-code-switch](https://github.com/foreveryh/claude-code-switch), stripped down to the essentials: **switch provider, set model, launch claude**.

## Features

- **9 built-in providers**: Anthropic, OpenRouter, DeepSeek, Z.AI, Kimi, Qwen, MiniMax, Doubao, Custom
- **Native login**: `ccs use claude` configures nothing at all — same account, same session as running `claude`, so keep-awake and sync work on your normal Claude subscription too
- **Default model**: configurable globally and per provider
- **Right-sized context window**: detects each model's real window so auto-compact stops assuming 200k
- **Config backup & sync**: push `~/.claude` to a gist or private repo, restore it on any machine
- **Keep awake**: `ccs caffeine on` stops the machine sleeping mid-session, for exactly as long as claude runs
- **Tiny footprint**: pure POSIX sh — no python, no node; `jq`, `llm-models`, `git` and `gh` are all optional, and each feature degrades instead of breaking when one is missing
- **Zero interference**: switching provider never touches your shell, your dotfiles or your Claude Code config. Only `ccs notify` and `ccs sync` write to `~/.claude` — both explicit opt-in, both reversible, both backed up first
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

Out of the box `ccs` is the native login: it launches `claude` untouched, on whatever account
`claude` is already logged into — you just get keep-awake, sync and provider switching around it.

```sh
ccs --caffeine            # your usual Claude session, machine kept awake
```

To bring another provider in:

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

And to stop rebuilding your Claude Code setup by hand on every new machine:

```sh
ccs sync init --gist-new   # 1. create a secret gist for it
ccs sync push              # 2. back up ~/.claude
ccs sync pull              # 3. …restore it anywhere else
```

## Usage

```
ccs [args...]               Launch claude with active provider (default)
ccs with <provider>[/<model>] [args...]
                            One launch with that provider, nothing saved
ccs <command> [arguments]

LAUNCH FLAGS
    --caffeine[=system|display] Keep the machine awake for this session only
    --no-caffeine               Let it sleep for this session only
    --relaunch / --no-relaunch  Relaunch when the usage limit resets, this session only
                                (must come first; everything else goes to claude)

COMMANDS
    use <provider> [model]      Switch to a provider (saves as default)
    list                        List configured providers
    status                      Show active provider and model
    config                      Open config file in $EDITOR
    config get <section> <key>  Print one config value (empty if unset)
    config set <section> <key> [value]
                                Set one value; no value = read it from stdin,
                                hidden when that is a terminal
    launch [args...]            Launch claude with active provider env vars
    with <provider>[/<model>]   Launch once with another provider (see above)
    env                         Print export statements for current shell
    models [refresh|clear]      Show / refresh the context windows ccs will use
    notify on|off|status|test   Desktop notifications when Claude needs you
    caffeine on|off|status      Keep the machine awake while claude runs
    relaunch on|off|status      Wait out the usage limit, then claude --continue
    sync <subcommand>           Back up ~/.claude to a gist or repo
    doctor                      Check the install: claude, tools, config, hooks
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
ccs use claude                        # Native login — exactly like running claude
ccs use anthropic                     # Native endpoint, with your own API key
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
ccs --caffeine -p "long refactor"     # ...and don't let the machine sleep
ccs --relaunch --caffeine -p "…"      # ...and pick up again when the usage limit resets

# One launch with another provider — the default stays what it was
ccs with deepseek -p "review this"    # DeepSeek for this run only
ccs with openrouter/openai/gpt-4o     # provider/model, split at the first slash
ccs with claude                       # the native login, once

# Export to current shell
eval "$(ccs env)"                     # Export env vars to current session
```

## Providers

All providers expose an Anthropic-compatible Messages API endpoint, confirmed working with Claude Code.
`claude` is the exception and the default: it is not an endpoint at all, just claude as it already runs.

| Provider     | Base URL                                                  | Default Model                    |
|--------------|-----------------------------------------------------------|----------------------------------|
| `claude`     | *(nothing injected — claude's own login)*                 | *(claude's own default)*         |
| `anthropic`  | *(native endpoint, your API key)*                         | `claude-sonnet-5`              |
| `openrouter` | `https://openrouter.ai/api`                               | `anthropic/claude-sonnet-4`      |
| `deepseek`   | `https://api.deepseek.com/anthropic`                      | `deepseek-chat`                  |
| `zai`        | `https://api.z.ai/api/anthropic`                          | `glm-5.1`                        |
| `kimi`       | `https://api.moonshot.ai/anthropic`                       | `kimi-k2.5`                      |
| `qwen`       | `https://dashscope-intl.aliyuncs.com/apps/anthropic`      | `qwen3.5-plus`                   |
| `minimax`    | `https://api.minimax.io/anthropic`                        | `MiniMax-M2.7`                   |
| `doubao`     | `https://ark.cn-beijing.volces.com/api/coding`            | `doubao-seed-code-preview-latest`|
| `custom`     | *(user-defined)*                                          | *(user-defined)*                 |

### Native login (`claude`)

`claude` is the default and the odd one out: it configures **nothing**. No base URL, no key, no
model, no context window — `ccs` exports not a single variable and simply runs `claude`, on
whatever account it is already logged into.

```sh
ccs use claude       # back to your normal Claude session
ccs --caffeine       # ...with the machine kept awake
```

That is the point: everything `ccs` wraps around the launch — keep awake, config sync, argument
passthrough — now works on a Claude subscription, not just on API keys. Switching to a provider and
back is one command each way.

It is stricter than plain `claude` on one point: the `ANTHROPIC_*` and `CLAUDE_CODE_*` variables
`ccs` manages are scrubbed from the environment first, so a stale `eval "$(ccs env)"` for another
provider cannot quietly survive into the session.

Don't confuse it with `anthropic`, which is the Anthropic endpoint **with your own API key**.

Any section can be a native login — `native=true` makes every other key in it irrelevant:

```ini
[claude]
native=true
```

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
provider=claude
model=
caffeine=off
relaunch=off

# Native login — nothing is injected, claude runs on its own account
[claude]
native=true

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
- **`native=`** — `true` makes the section the native login: ccs exports nothing and every other key
  in that section is ignored. That is what `[claude]` is
- **`model=`** — main model (maps to sonnet/default tier in `/models`)
- **`opus_model=`** — optional, for `/models` opus tier (falls back to `model`)
- **`haiku_model=`** — optional, for `/models` haiku tier + fast tasks (falls back to `model`)
- **`context_tokens=`** — optional, pins the context window (plain integer; empty means auto)
- **`max_output_tokens=`** — optional, pins the output limit (plain integer; empty means auto)
- **`auto_context=`** — in `[_defaults]`, set to `false` to disable the automatic lookup
- **`caffeine=`** — in `[_defaults]`, `off` (default), `system` or `display`; written by
  `ccs caffeine on|off` (see [Keep the machine awake](#keep-the-machine-awake))
- **`relaunch=`** — in `[_defaults]`, `off` (default) or `on`; written by `ccs relaunch on|off`
  (see [Relaunch when the usage limit resets](#relaunch-when-the-usage-limit-resets))

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

Values run to the end of the line, so no trailing comments. Spaces around `=` and around a
section header are ignored (`model = glm-5.1` works); a value keeps any further `=` it contains.

One value at a time, without opening the editor:

```sh
ccs config set zai api_key            # prompts for the value, hidden — no shell history
ccs config set zai api_key < key.txt  # or pipe it in
ccs config set _defaults caffeine display
ccs config get zai model              # prints the value, empty if unset
```

`config set` creates the section when it is missing. An `api_key=` changed this way is live at the
next launch: `ccs use` does not need to run again.

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

## Keep the machine awake

A long agent run and a laptop that sleeps at 15 minutes do not mix. `ccs caffeine on` holds an OS
sleep assertion for **exactly** as long as the claude process lives, then lets normal sleep
behaviour return on its own — whether the session exits, crashes or you Ctrl-C it. No permanent
system setting is changed.

```sh
ccs caffeine on              # Every session from now on
ccs caffeine on display      # ...and keep the screen lit too
ccs caffeine status          # Show the state and the exact wrapper
ccs caffeine off             # Back to normal sleep

ccs --caffeine               # Just this session
ccs --caffeine=display -p "long refactor"
ccs --no-caffeine            # Let this one sleep, whatever the config says
```

Two modes, because keeping the screen lit all night is rarely what you want:

| Mode | macOS | Linux (systemd) | Effect |
|---|---|---|---|
| `system` (default) | `caffeinate -ims` | `--what=sleep` | Machine stays awake, screen may sleep |
| `display` | `caffeinate -dims` | `--what=sleep:idle` | Screen stays lit too |

Linux falls back to `gnome-session-inhibit` when `systemd-inhibit` is absent.

**Platform support**, in full:

| Platform | Keep-awake |
|---|---|
| macOS | ✅ `caffeinate` |
| Linux (systemd) | ✅ `systemd-inhibit` |
| Linux (GNOME, no systemd) | ✅ `gnome-session-inhibit` |
| Linux, neither present | ⚠️ warns, launches normally |
| WSL | ⚠️ warns — a Linux VM cannot keep the Windows host awake, set it in Windows' power settings |
| Git Bash / MSYS / Cygwin | ⚠️ warns, launches normally |
| anything else (BSD…) | ⚠️ warns, launches normally |

There is no native Windows support: `ccs` is a POSIX shell script and cannot run there. In every
⚠️ case the session launches exactly as it would have — a missing keep-awake tool is never fatal,
and never silently pretends to have worked.

Two things worth knowing:

- A sleep assertion is a running process, not an environment variable, so `eval "$(ccs env)"`
  cannot carry it. Launch through `ccs` to get it (`ccs env` says so on stderr when caffeine is on).
- It prevents sleep, not a power cut. Commit your progress on long tasks.

The state lives in `[_defaults] caffeine=` in `~/.claude-provider/config` — nothing outside
`~/.claude-provider/` is touched, so this is *not* an exception to the zero-interference principle.

Not using `ccs`, or on native Windows? [claudfeine](https://github.com/maxgfr/claudfeine) is the
same idea as a standalone wrapper around `claude` (and `codex`), and ships a PowerShell wrapper
built on `SetThreadExecutionState` for Windows.

## Relaunch when the usage limit resets

```sh
ccs relaunch on                    # from now on
ccs --relaunch -p "finish the migration"   # this session only; --no-relaunch turns it off once
```

Claude Code stops on `You've hit your session limit · resets 1:10am (Europe/Berlin)`. With
relaunch on, ccs stays as claude's parent instead of `exec`ing it, reads that line when the session
ends on it, waits until the reset — keeping the machine awake if caffeine is on — then runs
`claude --continue` with the same provider and arguments, so the conversation picks up where it
stopped.

- **Interactive** — claude does not exit on the limit. Quit it after the message (Ctrl-C twice or
  `/exit`) and ccs takes over: it prints when it will be back and waits.
- **`-p` / piped** — automatic: claude exits with the message, ccs waits and reruns it. Give the
  prompt as an argument rather than on stdin, since stdin is gone by the second run.
- The relaunch is `claude --continue …`, the most recent conversation in the current directory. A
  `--continue` / `--resume` already in the arguments is respected, not duplicated.
- On a terminal the output is recorded through `script(1)` (macOS, util-linux, busybox) so the TUI
  keeps a real tty; on a pipe, through `tee`, stdout and stderr kept apart. The recording is a temp
  file removed as soon as the session ends — nothing is stored. Without `script`, ccs warns and runs
  claude as usual.
- The session wording (`resets 1:10am`) and the weekly one (`resets Sep 5 at 9am`) are both read,
  with the time zone in parentheses. If the reset time cannot be read, ccs says so and exits with
  claude's status.
- Ctrl-C during the wait gives up. For an overnight run combine it with caffeine:
  `ccs --relaunch --caffeine -p "…"`. `ccs env` cannot carry it, like caffeine.

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

## Check your install

```sh
ccs doctor
```

One line per check, read-only, no network. `ok` / `warn` / `fail`; the exit status is 1 only when
something is actually broken:

- **fail** — `claude` missing from `PATH`; the active provider has no key or is gone from the
  config; `~/.claude/settings.json` is not valid JSON; a ccs hook in it points to a script that no
  longer exists (regenerate with `ccs notify on` / `ccs sync hooks on`, or detach with `off`)
- **warn** — an optional tool is missing (`jq`, `git`, `llm-models`) with what that switches off;
  caffeine is on but no keep-awake tool works here (WSL included); a config section the parser
  skips; permissions looser than `700` on `~/.claude-provider` or `600` on `config` / `active`
- **info as ok** — the active provider, the sync remote and whether its working copy exists

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
ccs use claude  → ...and with no env vars at all: normal Claude Code, wrapped
```

`ccs` also **scrubs conflicting inherited vars** (`env -u`) before launching: a stale `ANTHROPIC_BASE_URL` or tier model left in your shell by a previous `eval "$(ccs env)"` for another provider can't leak into the launch. Likewise, `eval "$(ccs env)"` for native Anthropic unsets the third-party tier vars it may have exported before.

If **no provider is configured at all** (no active provider, no API key in the defaults), `ccs` warns and launches vanilla `claude` instead of failing.

With `ccs caffeine` on, the keep-awake tool is spliced into that same `exec`, between `env` and `claude` — `exec env ... caffeinate -ims claude ...` — so the sleep assertion is scoped to the claude process exactly like the env vars are, and claude's exit status still reaches your shell.

On the native login (`ccs use claude`) every variable in the table below is **unset**, not set:
that branch of the `exec` is nothing but `env -u ... claude`, plus the keep-awake wrapper.

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

The provider and model chosen with `ccs use` are persisted in `~/.claude-provider/active` so `ccs`
works across shell sessions. The key, endpoint and tier models are read from the config at every
launch, so editing `api_key=` is enough — no need to run `ccs use` again. Run `ccs reset` to clear
the active provider, or `ccs purge` to remove all ccs data.

Everything ccs owns lives in `~/.claude-provider/`: `config`, `active`, `models-cache`,
`hooks/` (notify + sync), `sync/` (the git working copy) and `sync-backup/` (the snapshots taken
before a restore). `ccs reset` only clears `active`; `ccs purge` removes the lot.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[MIT](LICENSE)

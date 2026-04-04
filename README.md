# claude-code-switch

Minimal, zero-dependency provider switching for [Claude Code](https://docs.anthropic.com/en/docs/claude-code). One shell script to rule them all.

Switch between AI providers (Anthropic, OpenRouter, DeepSeek, Z.AI, Kimi, Qwen, MiniMax, Doubao, or any custom endpoint) with a single command. **`claude` always works as-is** — `ccs` is a sidecar that only injects env vars when you explicitly run `ccs`.

Inspired by [foreveryh/claude-code-switch](https://github.com/foreveryh/claude-code-switch), stripped down to the essentials: **switch provider, set model, launch claude**.

## Features

- **9 built-in providers**: Anthropic, OpenRouter, DeepSeek, Z.AI, Kimi, Qwen, MiniMax, Doubao, Custom
- **Default model**: configurable globally and per provider
- **Zero dependencies**: pure POSIX sh — no jq, no python, no node
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

### Manual

```sh
# Download the script
curl -fsSL https://raw.githubusercontent.com/maxgfr/claude-code-switch/main/ccs -o /usr/local/bin/ccs
chmod +x /usr/local/bin/ccs

# First run creates ~/.claude-provider/config — add your API keys
ccs config
```

## Quick start

```sh
# 1. Add your API keys
ccs config

# 2. Switch to a provider
ccs use openrouter

# 3. Launch Claude Code
ccs
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
    reset                       Clear active provider (back to vanilla claude)
    purge                       Remove all ccs data (~/.claude-provider/)
    help                        Show help
    version                     Show version
```

### Examples

```sh
# Switch provider
ccs use anthropic                     # Use default model (claude-sonnet-4-6)
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
| `anthropic`  | *(native — no override)*                                  | `claude-sonnet-4-6`              |
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
model=claude-sonnet-4-6

[anthropic]
base_url=
api_key=sk-ant-your-key-here
model=claude-sonnet-4-6

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

State is persisted in `~/.claude-provider/active` so `ccs` works across shell sessions. Run `ccs reset` to clear it, or `ccs purge` to remove all ccs data.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[MIT](LICENSE)

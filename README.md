# claude-code-switch

Minimal, zero-dependency provider switching for [Claude Code](https://docs.anthropic.com/en/docs/claude-code). One shell script to rule them all.

Switch between AI providers (Anthropic, OpenRouter, DeepSeek, Gemini, Mistral, OpenAI, or any custom endpoint) with a single command. Configure a default model per provider and globally.

Inspired by [foreveryh/claude-code-switch](https://github.com/foreveryh/claude-code-switch), stripped down to the essentials: **switch provider, set model, launch claude**.

## Features

- **7 built-in providers**: Anthropic, OpenRouter, DeepSeek, Gemini, Mistral, OpenAI, Custom
- **Default model**: configurable globally and per provider
- **Zero dependencies**: pure POSIX sh — no jq, no python, no node
- **Shell integration**: `eval "$(ccs env)"` exports vars to your current session
- **Direct launch**: `ccs launch` starts Claude Code with the right env vars
- **API key validation**: clear errors when a provider is not configured
- **Masked secrets**: `ccs status` never leaks your full API key

## Installation

### Homebrew

```sh
brew install maxgfr/tap/claude-code-switch
```

### Manual

```sh
curl -fsSL https://raw.githubusercontent.com/maxgfr/claude-code-switch/main/ccs -o /usr/local/bin/ccs
chmod +x /usr/local/bin/ccs
ccs config  # creates ~/.claude-provider/config on first run
```

### From source

```sh
git clone https://github.com/maxgfr/claude-code-switch.git && cd claude-code-switch
./install.sh
```

## Quick start

```sh
# 1. Add your API keys
ccs config

# 2. Switch to a provider
ccs use openrouter

# 3. Launch Claude Code
ccs launch
```

## Usage

```
ccs <command> [arguments]

COMMANDS
    use <provider> [model]      Switch to a provider (optionally override model)
    list                        List configured providers
    status                      Show active provider and model
    config                      Open config file in $EDITOR
    default <provider> [model]  Set default provider and model
    launch [args...]            Launch claude with active provider env vars
    env                         Print export statements for current shell
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

# Set persistent defaults
ccs default openrouter               # Set OpenRouter as default provider
ccs default anthropic claude-opus-4-6 # Set default provider + model

# Check state
ccs list                              # See all providers and their status
ccs status                            # See active provider, model, masked API key

# Launch Claude Code
ccs launch                            # Launch with active provider
ccs launch --print "hello world"      # Pass flags through to claude

# Export to current shell
eval "$(ccs env)"                     # Export env vars to current session
```

## Providers

| Provider     | Base URL                                           | Default Model                  |
|--------------|----------------------------------------------------|---------------------------------|
| `anthropic`  | *(native — no override)*                           | `claude-sonnet-4-6`        |
| `openrouter` | `https://openrouter.ai/api/v1`                     | `anthropic/claude-sonnet-4`    |
| `deepseek`   | `https://api.deepseek.com/v1`                      | `deepseek-chat`                |
| `gemini`     | `https://generativelanguage.googleapis.com/v1beta/` | `gemini-2.5-pro`               |
| `mistral`    | `https://api.mistral.ai/v1`                        | `mistral-large-latest`         |
| `openai`     | `https://api.openai.com/v1`                        | `gpt-4o`                       |
| `custom`     | *(user-defined)*                                   | *(user-defined)*               |

## Configuration

Located at `~/.claude-provider/config`. Simple INI format, editable by hand:

```ini
[_defaults]
provider=anthropic
model=claude-sonnet-4-6

[anthropic]
base_url=
api_key=sk-ant-your-key-here
models=claude-sonnet-4-6,claude-opus-4-6,claude-haiku-4-5-20251001
default_model=claude-sonnet-4-6

[openrouter]
base_url=https://openrouter.ai/api/v1
api_key=sk-or-v1-your-key-here
models=anthropic/claude-sonnet-4,openai/gpt-4o,google/gemini-2.5-pro
default_model=anthropic/claude-sonnet-4
```

- **`[_defaults]`** — global default provider and model
- **`api_key=`** — empty means not configured
- **`base_url=`** — empty for `[anthropic]` uses native Anthropic API (no `ANTHROPIC_BASE_URL`)
- **`models=`** — comma-separated list of available models (informational + validation)
- **`default_model=`** — model used when none specified in `ccs use`

## Shell integration

Add to `~/.zshrc` or `~/.bashrc` so `ccs use` automatically exports env vars to your current shell:

```sh
ccs() {
    if [ "${1:-}" = "use" ] || [ "${1:-}" = "default" ]; then
        command ccs "$@" && eval "$(command ccs env)"
    else
        command ccs "$@"
    fi
}
```

## How it works

`ccs` sets these environment variables before launching Claude Code:

| Variable                       | When                                     |
|-------------------------------|------------------------------------------|
| `ANTHROPIC_BASE_URL`          | All providers except `anthropic` (unset for native) |
| `ANTHROPIC_API_KEY`           | Always                                   |
| `ANTHROPIC_MODEL`             | Always                                   |
| `CLAUDE_CODE_SUBAGENT_MODEL`  | Always (same value as `ANTHROPIC_MODEL`) |
| `ANTHROPIC_SMALL_FAST_MODEL`  | Non-Anthropic providers only             |

State is persisted in `~/.claude-provider/active` so `ccs launch` works across shell sessions.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[MIT](LICENSE)

# Changelog

All notable changes to this project will be documented in this file.

## [1.0.0] - 2026-04-03

### Features

- Provider switching via `ccs use <provider> [model]`
- Configurable default provider and model in `~/.claude-provider/config`
- INI-based configuration with 8 built-in providers (Anthropic, OpenRouter, DeepSeek, Z.AI, Kimi, Qwen, MiniMax, Custom)
- Environment variable export for shell integration (`ccs env`)
- Direct Claude Code launch with provider env vars (`ccs launch`)
- Provider listing with configuration status (`ccs list`)
- Active provider status display with masked API keys (`ccs status`)
- Config file management (`ccs config`)
- Default provider/model persistence (`ccs default`)
- POSIX sh compatible — zero external dependencies
- Homebrew installation support

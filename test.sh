#!/bin/sh
# test.sh — Integration tests for ccs
set -eu

CCS="$(cd "$(dirname "$0")" && pwd)/ccs"
PASS=0
FAIL=0
TEST_CONFIG_DIR=""

# --- Helpers ---

setup() {
    TEST_CONFIG_DIR=$(mktemp -d)
    export HOME="$TEST_CONFIG_DIR"
    # Trigger config creation
    "$CCS" help >/dev/null 2>&1
}

teardown() {
    rm -rf "$TEST_CONFIG_DIR"
}

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        PASS=$((PASS + 1))
        printf '  \033[32mPASS\033[0m %s\n' "$desc"
    else
        FAIL=$((FAIL + 1))
        printf '  \033[31mFAIL\033[0m %s\n' "$desc"
        printf '    expected: %s\n' "$expected"
        printf '    actual:   %s\n' "$actual"
    fi
}

assert_contains() {
    local desc="$1" needle="$2" haystack="$3"
    if printf '%s' "$haystack" | grep -qF "$needle"; then
        PASS=$((PASS + 1))
        printf '  \033[32mPASS\033[0m %s\n' "$desc"
    else
        FAIL=$((FAIL + 1))
        printf '  \033[31mFAIL\033[0m %s\n' "$desc"
        printf '    expected to contain: %s\n' "$needle"
        printf '    actual: %s\n' "$haystack"
    fi
}

assert_not_contains() {
    local desc="$1" needle="$2" haystack="$3"
    if ! printf '%s' "$haystack" | grep -qF "$needle"; then
        PASS=$((PASS + 1))
        printf '  \033[32mPASS\033[0m %s\n' "$desc"
    else
        FAIL=$((FAIL + 1))
        printf '  \033[31mFAIL\033[0m %s\n' "$desc"
        printf '    expected NOT to contain: %s\n' "$needle"
    fi
}

assert_exit() {
    local desc="$1" expected_code="$2"
    shift 2
    local actual_code=0
    "$@" >/dev/null 2>&1 || actual_code=$?
    assert_eq "$desc" "$expected_code" "$actual_code"
}

# Set all api_key= lines to a test value in the config
set_all_keys() {
    local keyval="$1"
    local cfg="$TEST_CONFIG_DIR/.claude-provider/config"
    local tmp="${cfg}.tmp"
    sed "s/^api_key=$/api_key=${keyval}/" "$cfg" > "$tmp"
    mv "$tmp" "$cfg"
}

# --- Tests ---

printf '\n\033[1m=== ccs test suite ===\033[0m\n\n'

# -- First run / config creation --
printf '\033[1m[config creation]\033[0m\n'
setup
assert_exit "first run creates config" "0" "$CCS" help
assert_eq "config file exists" "true" "$([ -f "$TEST_CONFIG_DIR/.claude-provider/config" ] && echo true || echo false)"
assert_eq "config dir is 700" "700" "$(stat -c '%a' "$TEST_CONFIG_DIR/.claude-provider" 2>/dev/null || stat -f '%A' "$TEST_CONFIG_DIR/.claude-provider" 2>/dev/null)"
teardown

# -- Version --
printf '\033[1m[version]\033[0m\n'
setup
out=$("$CCS" version)
assert_contains "version outputs ccs" "ccs" "$out"
teardown

# -- List providers --
printf '\033[1m[list]\033[0m\n'
setup
out=$("$CCS" list)
assert_contains "list shows anthropic" "anthropic" "$out"
assert_contains "list shows zai" "zai" "$out"
assert_contains "list shows doubao" "doubao" "$out"
assert_contains "list shows custom" "custom" "$out"
teardown

# -- Use provider --
printf '\033[1m[use]\033[0m\n'
setup
# Add a fake API key for zai
set_all_keys "test-key-123"
out=$("$CCS" use zai 2>&1)
assert_contains "use zai succeeds" "Switched to" "$out"
assert_contains "use zai shows provider" "zai" "$out"
assert_eq "active file exists" "true" "$([ -f "$TEST_CONFIG_DIR/.claude-provider/active" ] && echo true || echo false)"
active=$(cat "$TEST_CONFIG_DIR/.claude-provider/active")
assert_contains "active has correct provider" "PROVIDER=zai" "$active"
assert_contains "active has correct base_url" "BASE_URL=https://api.z.ai/api/anthropic" "$active"
assert_contains "active has correct model" "MODEL=glm-5.1" "$active"
assert_contains "active has opus_model" "OPUS_MODEL=glm-5.1" "$active"
assert_contains "active has sonnet_model" "SONNET_MODEL=glm-5.1" "$active"
assert_contains "active has haiku_model" "HAIKU_MODEL=glm-4.7" "$active"
config=$(cat "$TEST_CONFIG_DIR/.claude-provider/config")
assert_contains "use also sets default provider" "provider=zai" "$config"
assert_contains "use also sets default model" "model=glm-5.1" "$config"
teardown

# -- Use with model override --
printf '\033[1m[use with model override]\033[0m\n'
setup
set_all_keys "test-key-123"
"$CCS" use zai glm-4.7 >/dev/null 2>&1
active=$(cat "$TEST_CONFIG_DIR/.claude-provider/active")
assert_contains "model override works" "MODEL=glm-4.7" "$active"
teardown

# -- Use unknown provider fails --
printf '\033[1m[use unknown provider]\033[0m\n'
setup
assert_exit "unknown provider fails" "1" "$CCS" use fakeprovider
teardown

# -- Use without API key fails --
printf '\033[1m[use without api key]\033[0m\n'
setup
assert_exit "no api key fails" "1" "$CCS" use zai
teardown

# -- Status --
printf '\033[1m[status]\033[0m\n'
setup
set_all_keys "test-key-123"
"$CCS" use zai >/dev/null 2>&1
out=$("$CCS" status)
assert_contains "status shows provider" "zai" "$out"
assert_contains "status shows model" "glm-5.1" "$out"
assert_contains "status shows base url" "api.z.ai" "$out"
assert_contains "status masks short api key" "****" "$out"
assert_not_contains "status does not leak full key" "test-key-123" "$out"
teardown

# -- Status without active fails --
printf '\033[1m[status without active]\033[0m\n'
setup
assert_exit "status without active fails" "1" "$CCS" status
teardown

# -- Env output (third-party) --
printf '\033[1m[env third-party]\033[0m\n'
setup
set_all_keys "test-key-123"
"$CCS" use zai >/dev/null 2>&1
out=$("$CCS" env)
assert_contains "env uses ANTHROPIC_AUTH_TOKEN" "ANTHROPIC_AUTH_TOKEN" "$out"
assert_not_contains "env does not use ANTHROPIC_API_KEY export" "export ANTHROPIC_API_KEY" "$out"
assert_contains "env unsets ANTHROPIC_API_KEY" "unset ANTHROPIC_API_KEY" "$out"
assert_contains "env sets BASE_URL" "ANTHROPIC_BASE_URL" "$out"
assert_contains "env sets MODEL" "ANTHROPIC_MODEL" "$out"
assert_contains "env sets OPUS model" "ANTHROPIC_DEFAULT_OPUS_MODEL='glm-5.1'" "$out"
assert_contains "env sets SONNET model" "ANTHROPIC_DEFAULT_SONNET_MODEL='glm-5.1'" "$out"
assert_contains "env sets HAIKU model" "ANTHROPIC_DEFAULT_HAIKU_MODEL='glm-4.7'" "$out"
assert_contains "env sets SMALL_FAST to haiku" "ANTHROPIC_SMALL_FAST_MODEL='glm-4.7'" "$out"
assert_contains "env sets SUBAGENT to sonnet" "CLAUDE_CODE_SUBAGENT_MODEL='glm-5.1'" "$out"
assert_contains "env sets SUBAGENT_MODEL" "CLAUDE_CODE_SUBAGENT_MODEL" "$out"
teardown

# -- Env output (native anthropic) --
printf '\033[1m[env native anthropic]\033[0m\n'
setup
set_all_keys "sk-ant-test"
"$CCS" use anthropic >/dev/null 2>&1
out=$("$CCS" env)
assert_contains "native uses ANTHROPIC_API_KEY" "export ANTHROPIC_API_KEY" "$out"
assert_not_contains "native does not use AUTH_TOKEN export" "export ANTHROPIC_AUTH_TOKEN" "$out"
assert_contains "native unsets BASE_URL" "unset ANTHROPIC_BASE_URL" "$out"
assert_contains "native unsets AUTH_TOKEN" "unset ANTHROPIC_AUTH_TOKEN" "$out"
assert_not_contains "native does not export SMALL_FAST_MODEL" "export ANTHROPIC_SMALL_FAST_MODEL" "$out"
teardown

# -- Use persists as default --
printf '\033[1m[use persists default]\033[0m\n'
setup
set_all_keys "test-key-123"
"$CCS" use zai >/dev/null 2>&1
config=$(cat "$TEST_CONFIG_DIR/.claude-provider/config")
assert_contains "use sets default provider" "provider=zai" "$config"
assert_contains "use sets default model" "model=glm-5.1" "$config"
# Switch again
"$CCS" use deepseek >/dev/null 2>&1
config=$(cat "$TEST_CONFIG_DIR/.claude-provider/config")
assert_contains "switching updates default provider" "provider=deepseek" "$config"
assert_contains "switching updates default model" "model=deepseek-chat" "$config"
active=$(cat "$TEST_CONFIG_DIR/.claude-provider/active")
assert_contains "switching updates active" "PROVIDER=deepseek" "$active"
teardown

# -- Default command removed --
printf '\033[1m[default command removed]\033[0m\n'
setup
assert_exit "default command no longer exists" "1" "$CCS" default zai
teardown

# -- Reset --
printf '\033[1m[reset]\033[0m\n'
setup
set_all_keys "test-key-123"
"$CCS" use zai >/dev/null 2>&1
"$CCS" reset >/dev/null 2>&1
assert_eq "reset removes active file" "false" "$([ -f "$TEST_CONFIG_DIR/.claude-provider/active" ] && echo true || echo false)"
assert_exit "status after reset fails" "1" "$CCS" status
teardown

# -- Purge --
printf '\033[1m[purge]\033[0m\n'
setup
"$CCS" purge >/dev/null 2>&1
assert_eq "purge removes config dir" "false" "$([ -d "$TEST_CONFIG_DIR/.claude-provider" ] && echo true || echo false)"
teardown

# -- Section name validation (no hyphens) --
printf '\033[1m[section name validation]\033[0m\n'
setup
printf '\n[bad-name]\nbase_url=http://example.com\napi_key=test\nmodels=m1\ndefault_model=m1\n' >> "$TEST_CONFIG_DIR/.claude-provider/config"
assert_exit "hyphenated provider rejected" "1" "$CCS" use bad-name
teardown

# -- Unknown command --
printf '\033[1m[unknown command]\033[0m\n'
setup
assert_exit "unknown command fails" "1" "$CCS" doesnotexist
teardown

# -- Env native unsets stale tier vars --
printf '\033[1m[env native unsets tier vars]\033[0m\n'
setup
set_all_keys "sk-ant-test"
"$CCS" use anthropic >/dev/null 2>&1
out=$("$CCS" env)
assert_contains "native unsets OPUS tier" "unset ANTHROPIC_DEFAULT_OPUS_MODEL" "$out"
assert_contains "native unsets SONNET tier" "unset ANTHROPIC_DEFAULT_SONNET_MODEL" "$out"
assert_contains "native unsets HAIKU tier" "unset ANTHROPIC_DEFAULT_HAIKU_MODEL" "$out"
assert_contains "native unsets SUBAGENT model" "unset CLAUDE_CODE_SUBAGENT_MODEL" "$out"
assert_contains "native unsets SMALL_FAST model" "unset ANTHROPIC_SMALL_FAST_MODEL" "$out"
teardown

# -- Launch scrubs inherited env (fake claude shim) --
printf '\033[1m[launch scrubs inherited env]\033[0m\n'
setup
SHIM_DIR=$(mktemp -d)
printf '#!/bin/sh\nenv | grep -E "^(ANTHROPIC|CLAUDE_CODE)" || true\n' > "$SHIM_DIR/claude"
chmod +x "$SHIM_DIR/claude"
set_all_keys "sk-ant-test"
"$CCS" use anthropic >/dev/null 2>&1
out=$(PATH="$SHIM_DIR:$PATH" ANTHROPIC_BASE_URL="http://stale.example" \
      ANTHROPIC_DEFAULT_OPUS_MODEL="stale-model" "$CCS" launch 2>/dev/null)
assert_not_contains "native launch scrubs stale BASE_URL" "stale.example" "$out"
assert_not_contains "native launch scrubs stale tier model" "stale-model" "$out"
assert_contains "native launch keeps API key" "ANTHROPIC_API_KEY=sk-ant-test" "$out"
"$CCS" use zai >/dev/null 2>&1
out=$(PATH="$SHIM_DIR:$PATH" ANTHROPIC_API_KEY="stale-api-key" "$CCS" launch 2>/dev/null)
assert_not_contains "third-party launch scrubs stale API_KEY" "stale-api-key" "$out"
assert_contains "third-party launch sets AUTH_TOKEN" "ANTHROPIC_AUTH_TOKEN=sk-ant-test" "$out"
rm -rf "$SHIM_DIR"
teardown

# -- ccs -h / -v are ccs flags, not claude passthrough --
printf '\033[1m[-h and -v flags]\033[0m\n'
setup
out=$("$CCS" -h)
assert_contains "-h shows ccs help" "COMMANDS" "$out"
out=$("$CCS" --help)
assert_contains "--help shows ccs help" "COMMANDS" "$out"
out=$("$CCS" -v)
assert_contains "-v shows ccs version" "ccs" "$out"
out=$("$CCS" --version)
assert_contains "--version shows ccs version" "ccs" "$out"
teardown

# -- Vanilla fallback when nothing configured --
printf '\033[1m[vanilla fallback]\033[0m\n'
setup
SHIM_DIR=$(mktemp -d)
printf '#!/bin/sh\necho VANILLA_CLAUDE_RAN\n' > "$SHIM_DIR/claude"
chmod +x "$SHIM_DIR/claude"
# No API key configured anywhere → ccs should warn and run claude untouched
out=$(PATH="$SHIM_DIR:$PATH" "$CCS" launch 2>&1)
assert_contains "unconfigured ccs runs vanilla claude" "VANILLA_CLAUDE_RAN" "$out"
assert_contains "vanilla fallback warns" "vanilla" "$out"
rm -rf "$SHIM_DIR"
teardown

# -- Notify: install --
printf '\033[1m[notify on]\033[0m\n'
setup
SETTINGS="$TEST_CONFIG_DIR/.claude/settings.json"
HOOKS="$TEST_CONFIG_DIR/.claude-provider/hooks"
"$CCS" notify on >/dev/null 2>&1
assert_eq "emit hook created and executable" "true" "$([ -x "$HOOKS/notify-emit.sh" ] && echo true || echo false)"
assert_eq "stop hook created and executable" "true" "$([ -x "$HOOKS/notify-stop.sh" ] && echo true || echo false)"
assert_eq "attention hook created and executable" "true" "$([ -x "$HOOKS/notify-attention.sh" ] && echo true || echo false)"
assert_exit "settings.json is valid JSON" "0" jq empty "$SETTINGS"
settings=$(cat "$SETTINGS")
assert_contains "settings references stop hook" "notify-stop.sh" "$settings"
assert_contains "settings references attention hook" "notify-attention.sh" "$settings"
assert_contains "settings disables built-in channel" "notifications_disabled" "$settings"
assert_not_contains "settings has no SubagentStop hook" "SubagentStop" "$settings"
teardown

# -- Notify: preserves existing settings + idempotent --
printf '\033[1m[notify preserves settings]\033[0m\n'
setup
SETTINGS="$TEST_CONFIG_DIR/.claude/settings.json"
mkdir -p "$TEST_CONFIG_DIR/.claude"
printf '{"model":"opus","preferredNotifChannel":"iterm2"}\n' > "$SETTINGS"
"$CCS" notify on >/dev/null 2>&1
assert_eq "existing keys preserved" "opus" "$(jq -r '.model' "$SETTINGS")"
"$CCS" notify on >/dev/null 2>&1
assert_eq "idempotent: one Stop entry" "1" "$(jq '.hooks.Stop | length' "$SETTINGS")"
assert_eq "idempotent: one Notification entry" "1" "$(jq '.hooks.Notification | length' "$SETTINGS")"
"$CCS" notify off >/dev/null 2>&1
assert_eq "off restores previous channel" "iterm2" "$(jq -r '.preferredNotifChannel' "$SETTINGS")"
assert_eq "off removes hooks key when empty" "null" "$(jq -r '.hooks' "$SETTINGS")"
assert_eq "off keeps other settings" "opus" "$(jq -r '.model' "$SETTINGS")"
assert_eq "off removes hooks dir" "false" "$([ -d "$TEST_CONFIG_DIR/.claude-provider/hooks" ] && echo true || echo false)"
teardown

# -- Notify: off with no previous channel --
printf '\033[1m[notify off restores absent channel]\033[0m\n'
setup
SETTINGS="$TEST_CONFIG_DIR/.claude/settings.json"
"$CCS" notify on >/dev/null 2>&1
"$CCS" notify off >/dev/null 2>&1
assert_eq "channel absent again after off" "null" "$(jq -r '.preferredNotifChannel' "$SETTINGS")"
teardown

# -- Notify: pinned terminal + validation --
printf '\033[1m[notify terminal pinning]\033[0m\n'
setup
HOOKS="$TEST_CONFIG_DIR/.claude-provider/hooks"
"$CCS" notify on iterm2 >/dev/null 2>&1
assert_contains "method pinned in emit hook" 'CCS_NOTIFY_METHOD="iterm2"' "$(cat "$HOOKS/notify-emit.sh")"
out=$("$CCS" notify status)
assert_contains "status shows on + method" "on (iterm2)" "$out"
assert_exit "invalid terminal rejected" "1" "$CCS" notify on badterm
assert_exit "invalid subcommand rejected" "1" "$CCS" notify badsub
teardown

# -- Notify: status when off --
printf '\033[1m[notify status off]\033[0m\n'
setup
out=$("$CCS" notify status)
assert_contains "status shows off" "off" "$out"
teardown

# -- Notify: hooks behavior --
printf '\033[1m[notify hook scripts]\033[0m\n'
setup
HOOKS="$TEST_CONFIG_DIR/.claude-provider/hooks"
"$CCS" notify on ghostty >/dev/null 2>&1
out=$(printf '{}' | "$HOOKS/notify-stop.sh")
assert_contains "stop hook emits terminalSequence" "terminalSequence" "$out"
assert_contains "stop hook emits OSC 777" "777;notify" "$out"
out=$(printf '{"notification_type":"permission_prompt"}' | "$HOOKS/notify-attention.sh")
assert_contains "attention hook notifies on permission_prompt" "terminalSequence" "$out"
out=$(printf '{"notification_type":"agent_completed"}' | "$HOOKS/notify-attention.sh")
assert_eq "attention hook ignores agent_completed (subagents)" "" "$out"
assert_exit "notify test works when installed" "0" "$CCS" notify test
teardown

# -- Notify: refuses invalid settings.json --
printf '\033[1m[notify invalid settings]\033[0m\n'
setup
mkdir -p "$TEST_CONFIG_DIR/.claude"
printf 'not json' > "$TEST_CONFIG_DIR/.claude/settings.json"
assert_exit "notify on refuses broken settings.json" "1" "$CCS" notify on
teardown

# -- Notify: purge detaches hooks --
printf '\033[1m[purge detaches notify]\033[0m\n'
setup
SETTINGS="$TEST_CONFIG_DIR/.claude/settings.json"
"$CCS" notify on >/dev/null 2>&1
"$CCS" purge >/dev/null 2>&1
assert_not_contains "purge removes hook references" "claude-provider" "$(cat "$SETTINGS")"
assert_exit "settings still valid JSON after purge" "0" jq empty "$SETTINGS"
teardown

# -- Summary --
TOTAL=$((PASS + FAIL))
printf '\n\033[1m=== Results: %d/%d passed ===\033[0m\n' "$PASS" "$TOTAL"
if [ "$FAIL" -gt 0 ]; then
    printf '\033[31m%d test(s) failed\033[0m\n\n' "$FAIL"
    exit 1
else
    printf '\033[32mAll tests passed\033[0m\n\n'
    exit 0
fi

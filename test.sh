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
assert_eq "config dir is 700" "700" "$(stat -f '%A' "$TEST_CONFIG_DIR/.claude-provider" 2>/dev/null || stat -c '%a' "$TEST_CONFIG_DIR/.claude-provider" 2>/dev/null)"
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
assert_contains "active has sonnet_model" "SONNET_MODEL=glm-4.7" "$active"
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
assert_contains "env sets SONNET model" "ANTHROPIC_DEFAULT_SONNET_MODEL='glm-4.7'" "$out"
assert_contains "env sets HAIKU model" "ANTHROPIC_DEFAULT_HAIKU_MODEL='glm-4.7'" "$out"
assert_contains "env sets SMALL_FAST to haiku" "ANTHROPIC_SMALL_FAST_MODEL='glm-4.7'" "$out"
assert_contains "env sets SUBAGENT to sonnet" "CLAUDE_CODE_SUBAGENT_MODEL='glm-4.7'" "$out"
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
assert_not_contains "native does not set SMALL_FAST_MODEL" "ANTHROPIC_SMALL_FAST_MODEL" "$out"
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

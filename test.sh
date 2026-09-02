#!/bin/sh
# test.sh — Integration tests for ccs
set -eu

CCS="$(cd "$(dirname "$0")" && pwd)/ccs"
PASS=0
FAIL=0
TEST_CONFIG_DIR=""

# ccs consults llm-models for context windows. Shadow it with a deterministic
# stub for the whole suite so tests never touch the network: FAKE_LLM_MODELS
# holds the "ctx out id" answer, and unset means "no match" (exit 1), which is
# the behaviour every pre-existing test expects.
STUB_DIR=$(mktemp -d)
cat > "$STUB_DIR/llm-models" <<'STUB'
#!/bin/sh
[ "${1:-}" = "resolve" ] || exit 1
[ -n "${FAKE_LLM_MODELS:-}" ] || exit 1
printf '%s\n' "$FAKE_LLM_MODELS" | tr ' ' '\t'
STUB
chmod +x "$STUB_DIR/llm-models"
export PATH="$STUB_DIR:$PATH"
# A PATH with no llm-models on it, for the soft-dependency-absent tests
BARE_PATH="/usr/bin:/bin"
trap 'rm -rf "$STUB_DIR"' EXIT

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
    if printf '%s' "$haystack" | grep -qF -- "$needle"; then
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
    if ! printf '%s' "$haystack" | grep -qF -- "$needle"; then
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

# Set (or add) key=value inside a config section
set_key() {
    local section="$1" key="$2" value="$3"
    local cfg="$TEST_CONFIG_DIR/.claude-provider/config"
    local tmp="${cfg}.tmp"
    awk -v s="[$section]" -v k="$key" -v v="$value" '
        $0 == s { in_s = 1; print; next }
        /^\[/ {
            if (in_s && !done) { print k "=" v; done = 1 }
            in_s = 0; print; next
        }
        in_s && index($0, k "=") == 1 { print k "=" v; done = 1; next }
        { print }
        END { if (in_s && !done) print k "=" v }
    ' "$cfg" > "$tmp"
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
assert_contains "active has correct model" "MODEL=glm-5.1" "$active"
# The key and endpoint live in the config only: active names the provider,
# nothing more, so a key edited later is live at the next launch.
assert_not_contains "active carries no api key" "API_KEY" "$active"
assert_not_contains "active carries no base_url" "BASE_URL" "$active"
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

# -- Env output survives a single quote in a value --
printf '\033[1m[env quoting]\033[0m\n'
setup
set_all_keys "test-key-123"
"$CCS" use zai >/dev/null 2>&1
set_key zai api_key "sk-it's-x\$HOME\`id\`"
out=$(sh -c 'eval "$('"$CCS"' env)"; printf %s "$ANTHROPIC_AUTH_TOKEN"')
assert_eq "a quote in the key survives eval" "sk-it's-x\$HOME\`id\`" "$out"
set_key zai model "glm'5"
"$CCS" use zai >/dev/null 2>&1
out=$(sh -c 'eval "$('"$CCS"' env)"; printf %s "$ANTHROPIC_MODEL"')
assert_eq "a quote in the model survives eval" "glm'5" "$out"
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

# -- Config parsing: whitespace, = inside values, comments --
printf '\033[1m[config parsing]\033[0m\n'
setup
CFG="$TEST_CONFIG_DIR/.claude-provider/config"
printf '\n  [spaced]  \nbase_url = https://spaced.example/v1  \napi_key = spaced-key\n  model = glm=5.1\n# a comment inside the section\n\n[bad name]\napi_key=x\n' >> "$CFG"
out=$("$CCS" use spaced 2>&1 || true)
assert_contains "key = value with spaces resolves the model" "glm=5.1" "$out"
out=$("$CCS" env 2>/dev/null || true)
assert_contains "value keeps its inner = and loses outer spaces" "ANTHROPIC_BASE_URL='https://spaced.example/v1'" "$out"
assert_contains "api key with spaces around = is read" "ANTHROPIC_AUTH_TOKEN='spaced-key'" "$out"
assert_contains "section header with surrounding spaces is a provider" "spaced" "$("$CCS" list 2>/dev/null)"
assert_contains "invalid section name is still reported" "Skipping invalid section name: bad name" "$("$CCS" list 2>&1)"
assert_not_contains "invalid section is not a provider" "bad name" "$("$CCS" list 2>/dev/null)"
config=$(cat "$CFG")
assert_contains "use rewrites provider= in [_defaults]" "provider=spaced" "$config"
assert_contains "use rewrites model= in [_defaults]" "model=glm=5.1" "$config"
assert_contains "use leaves the provider section's model alone" "  model = glm=5.1" "$config"
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

# -- The config is the source of truth for key and endpoint at launch --
printf '\033[1m[live config at launch]\033[0m\n'
setup
SHIM_DIR=$(mktemp -d)
printf '#!/bin/sh\nenv | grep -E "^(ANTHROPIC|CLAUDE_CODE)" || true\n' > "$SHIM_DIR/claude"
chmod +x "$SHIM_DIR/claude"
set_all_keys "test-key-123"
"$CCS" use zai >/dev/null 2>&1
set_key zai api_key "rotated-key-0123456789"
set_key zai base_url "https://moved.example/anthropic"
set_key zai haiku_model "glm-4.7-flash"
out=$(PATH="$SHIM_DIR:$PATH" "$CCS" launch 2>/dev/null)
assert_contains "launch sends the key now in the config" "ANTHROPIC_AUTH_TOKEN=rotated-key-0123456789" "$out"
assert_contains "launch uses the base_url now in the config" "ANTHROPIC_BASE_URL=https://moved.example/anthropic" "$out"
assert_contains "launch uses the tier now in the config" "ANTHROPIC_DEFAULT_HAIKU_MODEL=glm-4.7-flash" "$out"
assert_contains "launch keeps the model chosen with use" "ANTHROPIC_MODEL=glm-5.1" "$out"
out=$("$CCS" env)
assert_contains "env follows the config too" "ANTHROPIC_AUTH_TOKEN='rotated-key-0123456789'" "$out"
out=$("$CCS" status)
assert_contains "status shows the current key, masked" "rotated-...6789" "$out"
assert_contains "status shows the current base url" "moved.example" "$out"
# A model chosen with `use <provider> <model>` survives a config edit
"$CCS" use zai glm-4.7 >/dev/null 2>&1
set_key zai api_key "another-key"
out=$(PATH="$SHIM_DIR:$PATH" "$CCS" launch 2>/dev/null)
assert_contains "explicit model survives a key rotation" "ANTHROPIC_MODEL=glm-4.7" "$out"
assert_contains "and the rotated key is used" "ANTHROPIC_AUTH_TOKEN=another-key" "$out"
# A blanked key is an error, not a silent launch with an empty token
set_key zai api_key ""
err=$(PATH="$SHIM_DIR:$PATH" "$CCS" launch 2>&1 || true)
assert_contains "a blanked key stops the launch" "no API key" "$err"
assert_exit "with a non-zero exit" "1" "$CCS" launch
assert_exit "env fails the same way" "1" "$CCS" env
# An active file from before this change still carries a key: honour it when
# its section is gone from the config, so nothing breaks on upgrade
ACTIVE="$TEST_CONFIG_DIR/.claude-provider/active"
printf 'PROVIDER=legacy\nMODEL=old-model\nBASE_URL=https://legacy.example/v1\nAPI_KEY=legacy-key\nOPUS_MODEL=old-opus\nSONNET_MODEL=old-model\nHAIKU_MODEL=old-haiku\nNATIVE=\n' > "$ACTIVE"
out=$(PATH="$SHIM_DIR:$PATH" "$CCS" launch 2>/dev/null)
assert_contains "legacy active file: key still used" "ANTHROPIC_AUTH_TOKEN=legacy-key" "$out"
assert_contains "legacy active file: base_url still used" "ANTHROPIC_BASE_URL=https://legacy.example/v1" "$out"
assert_contains "legacy active file: tiers still used" "ANTHROPIC_DEFAULT_OPUS_MODEL=old-opus" "$out"
# A provider removed from the config with no key on record cannot launch
printf 'PROVIDER=gone\nMODEL=m\nNATIVE=\n' > "$ACTIVE"
err=$(PATH="$SHIM_DIR:$PATH" "$CCS" launch 2>&1 || true)
assert_contains "a vanished provider says so" "no longer in the config" "$err"
rm -rf "$SHIM_DIR"
teardown

# -- config get / set --
printf '\033[1m[config set and get]\033[0m\n'
setup
CFG="$TEST_CONFIG_DIR/.claude-provider/config"
out=$(EDITOR=/bin/cat "$CCS" config)
assert_contains "config alone opens the file in EDITOR" "[_defaults]" "$out"
"$CCS" config set zai api_key "set-key-1" >/dev/null 2>&1
assert_eq "get returns what set wrote" "set-key-1" "$("$CCS" config get zai api_key)"
assert_eq "get of an absent key prints nothing" "" "$("$CCS" config get zai nothing)"
assert_exit "and still exits 0" "0" "$CCS" config get zai nothing
"$CCS" config set newprov model "m1" >/dev/null 2>&1
assert_contains "set creates a missing section" "[newprov]" "$(cat "$CFG")"
assert_eq "and the key inside it" "m1" "$("$CCS" config get newprov model)"
printf 'piped-key\n' | "$CCS" config set zai api_key >/dev/null 2>&1
assert_eq "set without a value reads stdin" "piped-key" "$("$CCS" config get zai api_key)"
"$CCS" config set zai api_key "" >/dev/null 2>&1
assert_eq "an empty value blanks the key" "" "$("$CCS" config get zai api_key)"
out=$("$CCS" config set zai api_key "secret-value-1234567" 2>&1)
assert_not_contains "set never echoes a key back" "secret-value-1234567" "$out"
assert_contains "but confirms the write" "api_key" "$out"
"$CCS" config set _defaults caffeine display >/dev/null 2>&1
assert_contains "reserved sections are writable" "on (display" "$("$CCS" caffeine status)"
assert_exit "invalid section name rejected" "1" "$CCS" config set "bad name" k v
assert_exit "invalid key name rejected" "1" "$CCS" config set zai "bad-key" v
assert_exit "get needs section and key" "1" "$CCS" config get zai
assert_exit "unknown subcommand rejected" "1" "$CCS" config bogus
assert_eq "config file is still 600" "600" "$(stat -c '%a' "$CFG" 2>/dev/null || stat -f '%A' "$CFG" 2>/dev/null)"
# A key set this way is live at the next launch — no `ccs use` needed
SHIM_DIR=$(mktemp -d)
printf '#!/bin/sh\nenv | grep -E "^(ANTHROPIC|CLAUDE_CODE)" || true\n' > "$SHIM_DIR/claude"
chmod +x "$SHIM_DIR/claude"
"$CCS" use zai >/dev/null 2>&1
"$CCS" config set zai api_key "fresh-key" >/dev/null 2>&1
out=$(PATH="$SHIM_DIR:$PATH" "$CCS" launch 2>/dev/null)
assert_contains "a key set with config set is used at launch" "ANTHROPIC_AUTH_TOKEN=fresh-key" "$out"
rm -rf "$SHIM_DIR"
teardown

# -- doctor: read-only checks, exit 1 only on a fail --
printf '\033[1m[doctor]\033[0m\n'
setup
CFG="$TEST_CONFIG_DIR/.claude-provider/config"
SETTINGS="$TEST_CONFIG_DIR/.claude/settings.json"
SHIM_DIR=$(mktemp -d)
printf '#!/bin/sh\necho CLAUDE_RAN\n' > "$SHIM_DIR/claude"
chmod +x "$SHIM_DIR/claude"
# A PATH with everything ccs needs and nothing optional: no claude, no jq,
# no git, no llm-models, no keep-awake tool
BARE_DIR=$(mktemp -d)
for b in sh sed awk grep find mkdir mktemp date cat cp rm mv ls chmod rmdir \
         head tail tr wc uname diff sort stat env dirname basename rev cut \
         touch sleep kill expr; do
    p=$(command -v "$b" 2>/dev/null) && ln -sf "$p" "$BARE_DIR/$b"
done
out=$(PATH="$SHIM_DIR:$PATH" "$CCS" doctor 2>&1)
assert_exit "a fresh install is healthy" "0" env PATH="$SHIM_DIR:$PATH" "$CCS" doctor
assert_contains "doctor finds claude" "claude" "$out"
assert_contains "doctor reports the native default" "claude" "$out"
assert_not_contains "nothing fails on a fresh install" "fail" "$out"
out=$(PATH="$BARE_DIR" "$CCS" doctor 2>&1 || true)
assert_exit "no claude on PATH is a fail" "1" env PATH="$BARE_DIR" "$CCS" doctor
assert_contains "and says so" "claude" "$out"
assert_contains "missing jq is a warn naming notify" "notify" "$out"
assert_contains "missing git is a warn naming sync" "sync" "$out"
assert_contains "missing llm-models is a warn naming the window" "llm-models" "$out"
# Active provider checks
set_all_keys "test-key-123"
"$CCS" use zai >/dev/null 2>&1
out=$(PATH="$SHIM_DIR:$PATH" "$CCS" doctor 2>&1)
assert_contains "doctor shows the active provider" "zai" "$out"
"$CCS" config set zai api_key "" >/dev/null 2>&1
out=$(PATH="$SHIM_DIR:$PATH" "$CCS" doctor 2>&1 || true)
assert_exit "active provider without a key is a fail" "1" env PATH="$SHIM_DIR:$PATH" "$CCS" doctor
assert_contains "and names the fix" "config set zai api_key" "$out"
printf 'PROVIDER=gone\nMODEL=m\nNATIVE=\n' > "$TEST_CONFIG_DIR/.claude-provider/active"
out=$(PATH="$SHIM_DIR:$PATH" "$CCS" doctor 2>&1 || true)
assert_contains "a vanished provider is a fail" "no longer in the config" "$out"
"$CCS" use claude >/dev/null 2>&1
# Config hygiene
printf '\n[bad name]\nx=1\n' >> "$CFG"
out=$(PATH="$SHIM_DIR:$PATH" "$CCS" doctor 2>&1)
assert_contains "an invalid section is a warn" "bad name" "$out"
assert_exit "but not a fail" "0" env PATH="$SHIM_DIR:$PATH" "$CCS" doctor
chmod 644 "$CFG"
out=$(PATH="$SHIM_DIR:$PATH" "$CCS" doctor 2>&1)
assert_contains "a world-readable config is a warn" "600" "$out"
chmod 600 "$CFG"
# Keep-awake
"$CCS" caffeine on >/dev/null 2>&1
out=$(PATH="$SHIM_DIR:$BARE_DIR" "$CCS" doctor 2>&1 || true)
assert_contains "caffeine on without a tool is a warn" "keep-awake" "$out"
"$CCS" caffeine off >/dev/null 2>&1
# settings.json: broken JSON, then an orphan ccs hook
mkdir -p "$TEST_CONFIG_DIR/.claude"
printf '{not json' > "$SETTINGS"
out=$(PATH="$SHIM_DIR:$PATH" "$CCS" doctor 2>&1 || true)
assert_exit "invalid settings.json is a fail" "1" env PATH="$SHIM_DIR:$PATH" "$CCS" doctor
assert_contains "and is named" "settings.json" "$out"
printf '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"%s/.claude-provider/hooks/notify-stop.sh"}]}]}}\n' \
    "$TEST_CONFIG_DIR" > "$SETTINGS"
out=$(PATH="$SHIM_DIR:$PATH" "$CCS" doctor 2>&1 || true)
assert_exit "an orphan ccs hook is a fail" "1" env PATH="$SHIM_DIR:$PATH" "$CCS" doctor
assert_contains "and points at the script" "notify-stop.sh" "$out"
assert_contains "and suggests the fix" "ccs notify on" "$out"
"$CCS" notify on bell >/dev/null 2>&1
out=$(PATH="$SHIM_DIR:$PATH" "$CCS" doctor 2>&1)
assert_exit "a live ccs hook is fine" "0" env PATH="$SHIM_DIR:$PATH" "$CCS" doctor
assert_contains "and is counted" "hook" "$out"
# Sync: remote shown, no network
"$CCS" config set _sync remote "https://example.invalid/x.git" >/dev/null 2>&1
out=$(PATH="$SHIM_DIR:$PATH" "$CCS" doctor 2>&1 || true)
assert_contains "the sync remote is reported" "example.invalid" "$out"
assert_contains "and a missing working copy is mentioned" "working copy" "$out"
rm -rf "$SHIM_DIR" "$BARE_DIR"
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
# The shipped default is the native [claude] provider, which is a deliberate
# choice, not an unconfigured state. Point the default at a keyless provider to
# get the genuinely-unconfigured case this fallback exists for.
set_key _defaults provider anthropic
# No API key configured anywhere → ccs should warn and run claude untouched
out=$(PATH="$SHIM_DIR:$PATH" "$CCS" launch 2>&1)
assert_contains "unconfigured ccs runs vanilla claude" "VANILLA_CLAUDE_RAN" "$out"
assert_contains "vanilla fallback warns" "vanilla" "$out"
rm -rf "$SHIM_DIR"
teardown

# --- Native login ([claude], native=true) ---------------------------------
# The one provider that configures nothing: launching through ccs must be
# indistinguishable from running claude, while ccs still wraps the process.

# A shim that reports exactly the variables ccs owns — the harness's own
# CLAUDE_CODE_* vars would otherwise show up on a developer machine.
native_shim() {
    SHIM_DIR=$(mktemp -d)
    printf '#!/bin/sh\necho "CLAUDE_ARGV:$*"\nenv | grep -E "^(ANTHROPIC_|CLAUDE_CODE_MAX_|CLAUDE_CODE_SUBAGENT_)" || echo NO_PROVIDER_VARS\n' \
        > "$SHIM_DIR/claude"
    chmod +x "$SHIM_DIR/claude"
}

printf '\033[1m[native use]\033[0m\n'
setup
ACTIVE="$TEST_CONFIG_DIR/.claude-provider/active"
CFG="$TEST_CONFIG_DIR/.claude-provider/config"
out=$("$CCS" use claude 2>&1)
assert_contains "use claude works with no key anywhere" "native login" "$out"
assert_contains "active records the provider" "PROVIDER=claude" "$(cat "$ACTIVE")"
assert_contains "active records native mode" "NATIVE=1" "$(cat "$ACTIVE")"
assert_eq "active carries no model" "MODEL=" "$(grep '^MODEL=' "$ACTIVE")"
assert_not_contains "active carries no key" "API_KEY" "$(cat "$ACTIVE")"
assert_contains "defaults follow" "provider=claude" "$(cat "$CFG")"
assert_eq "defaults carry no model either" "model=" \
    "$(awk '/^\[/ { s = $0 } s == "[_defaults]" && /^model=/ { print }' "$CFG")"
assert_exit "the native login takes no model" "1" "$CCS" use claude glm-5.3
set_all_keys "sk-ant-test"
"$CCS" use zai >/dev/null 2>&1
assert_eq "switching away clears native mode" "NATIVE=" "$(grep '^NATIVE=' "$ACTIVE")"
teardown

printf '\033[1m[native launch]\033[0m\n'
setup
native_shim
"$CCS" use claude >/dev/null 2>&1
out=$(PATH="$SHIM_DIR:$PATH" \
      ANTHROPIC_BASE_URL="http://stale.example" \
      ANTHROPIC_API_KEY="stale-key" \
      ANTHROPIC_AUTH_TOKEN="stale-token" \
      ANTHROPIC_MODEL="stale-model" \
      ANTHROPIC_DEFAULT_OPUS_MODEL="stale-opus" \
      CLAUDE_CODE_MAX_CONTEXT_TOKENS="999999" \
      "$CCS" launch -p hi 2>/dev/null)
assert_contains "native launch injects nothing" "NO_PROVIDER_VARS" "$out"
assert_not_contains "native launch scrubs an inherited base url" "stale.example" "$out"
assert_not_contains "native launch scrubs an inherited api key" "stale-key" "$out"
assert_not_contains "native launch scrubs an inherited auth token" "stale-token" "$out"
assert_not_contains "native launch scrubs an inherited model" "stale-model" "$out"
assert_not_contains "native launch scrubs an inherited tier model" "stale-opus" "$out"
assert_not_contains "native launch scrubs an inherited context window" "999999" "$out"
assert_contains "claude keeps its own arguments" "CLAUDE_ARGV:-p hi" "$out"
err=$(PATH="$SHIM_DIR:$PATH" "$CCS" launch 2>&1 >/dev/null)
assert_not_contains "native mode is not the vanilla fallback" "vanilla" "$err"
rm -rf "$SHIM_DIR"
teardown

printf '\033[1m[native is the shipped default]\033[0m\n'
setup
native_shim
out=$(PATH="$SHIM_DIR:$PATH" "$CCS" -p hi 2>&1)
assert_contains "a fresh install launches the native login" "native login" "$out"
assert_not_contains "a fresh install no longer warns" "vanilla" "$out"
assert_contains "claude runs untouched" "NO_PROVIDER_VARS" "$out"
rm -rf "$SHIM_DIR"
teardown

printf '\033[1m[native env]\033[0m\n'
setup
"$CCS" use claude >/dev/null 2>&1
out=$("$CCS" env 2>/dev/null)
assert_not_contains "native env exports nothing" "export " "$out"
assert_contains "native env unsets the api key" "unset ANTHROPIC_API_KEY" "$out"
assert_contains "native env unsets the auth token" "unset ANTHROPIC_AUTH_TOKEN" "$out"
assert_contains "native env unsets the base url" "unset ANTHROPIC_BASE_URL" "$out"
assert_contains "native env unsets the model" "unset ANTHROPIC_MODEL" "$out"
assert_contains "native env unsets the context window" "unset CLAUDE_CODE_MAX_CONTEXT_TOKENS" "$out"
assert_exit "the output is valid shell" "0" sh -c "eval \"\$('$CCS' env 2>/dev/null)\""
teardown

printf '\033[1m[native status, list and models]\033[0m\n'
setup
"$CCS" use claude >/dev/null 2>&1
out=$("$CCS" status)
assert_contains "status names the provider" "claude" "$out"
assert_contains "status says native login" "native login" "$out"
assert_not_contains "status has no key to show" "API Key" "$out"
assert_not_contains "status has no window to show" "Context:" "$out"
assert_contains "status still reports keep awake" "Caffeine:" "$out"
out=$("$CCS" list)
assert_contains "list marks it native, not unconfigured" "native login" "$out"
out=$("$CCS" models 2>&1)
assert_contains "models explains there is nothing to size" "own model table" "$out"
assert_exit "models exits clean in native mode" "0" "$CCS" models
teardown

printf '\033[1m[native migration of an older config]\033[0m\n'
setup
CFG="$TEST_CONFIG_DIR/.claude-provider/config"
cat > "$CFG" <<'OLD'
[_defaults]
provider=zai
model=glm-5.3

[zai]
base_url=https://api.z.ai/api/anthropic
api_key=sk-zai-test
model=glm-5.3
OLD
"$CCS" list >/dev/null 2>&1
cfg=$(cat "$CFG")
assert_contains "migration adds a [claude] section" "[claude]" "$cfg"
assert_contains "migration marks it native" "native=true" "$cfg"
assert_contains "migration keeps the existing default provider" "provider=zai" "$cfg"
assert_contains "migration keeps the existing default model" "model=glm-5.3" "$cfg"
assert_contains "migration keeps the existing api key" "api_key=sk-zai-test" "$cfg"
"$CCS" list >/dev/null 2>&1
"$CCS" status >/dev/null 2>&1 || true
assert_eq "migration runs exactly once" "1" "$(grep -c '^native=true$' "$CFG")"
assert_exit "use claude works afterwards" "0" "$CCS" use claude
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

# -- Context window: pinned via config --
printf '\033[1m[context window: config pin]\033[0m\n'
setup
set_all_keys "test-key-123"
set_key zai context_tokens 123456
set_key zai max_output_tokens 4096
"$CCS" use zai >/dev/null 2>&1
out=$("$CCS" env)
assert_contains "env exports pinned context" "export CLAUDE_CODE_MAX_CONTEXT_TOKENS='123456'" "$out"
assert_contains "env exports pinned output limit" "export CLAUDE_CODE_MAX_OUTPUT_TOKENS='4096'" "$out"
out=$("$CCS" status)
assert_contains "status shows the window" "123K" "$out"
assert_contains "status names the source" "config" "$out"
teardown

# -- Context window: launch injects the vars --
printf '\033[1m[context window: launch]\033[0m\n'
setup
SHIM_DIR=$(mktemp -d)
printf '#!/bin/sh\nenv | grep -E "^(ANTHROPIC|CLAUDE_CODE)" || true\n' > "$SHIM_DIR/claude"
chmod +x "$SHIM_DIR/claude"
set_all_keys "test-key-123"
set_key zai context_tokens 123456
"$CCS" use zai >/dev/null 2>&1
out=$(PATH="$SHIM_DIR:$PATH" "$CCS" launch 2>/dev/null)
assert_contains "third-party launch sets context tokens" "CLAUDE_CODE_MAX_CONTEXT_TOKENS=123456" "$out"
# Native Anthropic must stay untouched, and stale values must not leak in
"$CCS" use anthropic >/dev/null 2>&1
out=$(PATH="$SHIM_DIR:$PATH" CLAUDE_CODE_MAX_CONTEXT_TOKENS="999999" "$CCS" launch 2>/dev/null)
assert_not_contains "native launch scrubs inherited context tokens" "999999" "$out"
assert_not_contains "native launch sets no context tokens" "CLAUDE_CODE_MAX_CONTEXT_TOKENS" "$out"
rm -rf "$SHIM_DIR"
teardown

# -- Context window: unknown model leaves ccs untouched --
printf '\033[1m[context window: unknown model]\033[0m\n'
setup
set_all_keys "test-key-123"
"$CCS" use zai >/dev/null 2>&1
out=$("$CCS" env)
assert_contains "env unsets context tokens when unknown" "unset CLAUDE_CODE_MAX_CONTEXT_TOKENS" "$out"
assert_not_contains "env exports no context tokens when unknown" "export CLAUDE_CODE_MAX_CONTEXT_TOKENS" "$out"
out=$("$CCS" status)
assert_contains "status reports unknown" "unknown" "$out"
teardown

# -- Context window: auto_context=false disables the lookup --
printf '\033[1m[context window: auto_context=false]\033[0m\n'
setup
set_all_keys "test-key-123"
set_key _defaults auto_context false
"$CCS" use zai >/dev/null 2>&1
out=$(FAKE_LLM_MODELS="1000000 131072 zai-coding-plan/glm-5.3" "$CCS" env)
assert_not_contains "auto_context=false exports nothing" "export CLAUDE_CODE_MAX_CONTEXT_TOKENS" "$out"
out=$(FAKE_LLM_MODELS="1000000 131072 zai-coding-plan/glm-5.3" "$CCS" status)
assert_contains "status reports off" "off" "$out"
teardown

# -- Context window: a non-numeric pin is rejected, not exported --
printf '\033[1m[context window: invalid pin]\033[0m\n'
setup
set_all_keys "test-key-123"
set_key zai context_tokens "200k"
"$CCS" use zai >/dev/null 2>&1
out=$("$CCS" env 2>/dev/null)
assert_not_contains "non-numeric pin is not exported" "export CLAUDE_CODE_MAX_CONTEXT_TOKENS" "$out"
err=$("$CCS" env 2>&1 >/dev/null)
assert_contains "non-numeric pin warns" "non-numeric context_tokens" "$err"
teardown

# -- Context window: resolved from llm-models, then cached --
printf '\033[1m[context window: llm-models lookup + cache]\033[0m\n'
setup
set_all_keys "test-key-123"
FAKE_LLM_MODELS="1000000 131072 zai-coding-plan/glm-5.3" "$CCS" use zai >/dev/null 2>&1
cache="$TEST_CONFIG_DIR/.claude-provider/models-cache"
assert_eq "use writes the cache" "true" "$([ -f "$cache" ] && echo true || echo false)"
assert_contains "cache records the window" "zai glm-5.1 1000000 131072" "$(cat "$cache")"
assert_contains "cache records the resolved id" "zai-coding-plan/glm-5.3" "$(cat "$cache")"
assert_eq "cache file is 600" "600" "$(stat -c '%a' "$cache" 2>/dev/null || stat -f '%A' "$cache" 2>/dev/null)"
# The cache answers without llm-models being consulted again
out=$("$CCS" env)
assert_contains "cached window is exported" "export CLAUDE_CODE_MAX_CONTEXT_TOKENS='1000000'" "$out"
assert_contains "cached output limit is exported" "export CLAUDE_CODE_MAX_OUTPUT_TOKENS='131072'" "$out"
out=$("$CCS" status)
assert_contains "status credits the cache" "cache" "$out"
teardown

# -- Context window: an output limit above the window is clamped --
printf '\033[1m[context window: output clamped to window]\033[0m\n'
setup
set_all_keys "test-key-123"
FAKE_LLM_MODELS="200000 384000 deepseek/deepseek-chat" "$CCS" use deepseek >/dev/null 2>&1
out=$("$CCS" env)
assert_contains "output limit clamped to the window" "export CLAUDE_CODE_MAX_OUTPUT_TOKENS='200000'" "$out"
teardown

# -- ccs models --
printf '\033[1m[models command]\033[0m\n'
setup
set_all_keys "test-key-123"
FAKE_LLM_MODELS="1000000 131072 zai-coding-plan/glm-5.3" "$CCS" use zai >/dev/null 2>&1
out=$("$CCS" models)
assert_contains "models lists the main tier" "main" "$out"
assert_contains "models shows the window" "1.0M" "$out"
assert_contains "models shows the resolved id" "zai-coding-plan/glm-5.3" "$out"
assert_contains "models lists the haiku tier" "haiku" "$out"
assert_exit "models rejects an unknown action" "1" "$CCS" models bogus
"$CCS" models clear >/dev/null 2>&1
assert_eq "models clear removes the cache" "false" \
    "$([ -f "$TEST_CONFIG_DIR/.claude-provider/models-cache" ] && echo true || echo false)"
teardown

# -- Soft dependency: ccs works with no llm-models on PATH --
printf '\033[1m[llm-models absent]\033[0m\n'
setup
set_all_keys "test-key-123"
PATH="$BARE_PATH" "$CCS" use zai >/dev/null 2>&1
out=$(PATH="$BARE_PATH" "$CCS" env)
assert_contains "still exports the model" "ANTHROPIC_MODEL" "$out"
assert_not_contains "exports no context tokens" "export CLAUDE_CODE_MAX_CONTEXT_TOKENS" "$out"
out=$(PATH="$BARE_PATH" "$CCS" status)
assert_contains "status explains the missing dependency" "no llm-models" "$out"
teardown

# -- purge removes the model cache --
printf '\033[1m[purge removes model cache]\033[0m\n'
setup
set_all_keys "test-key-123"
FAKE_LLM_MODELS="1000000 131072 zai/glm-5.1" "$CCS" use zai >/dev/null 2>&1
"$CCS" purge >/dev/null 2>&1
assert_eq "purge removes the whole dir" "false" \
    "$([ -d "$TEST_CONFIG_DIR/.claude-provider" ] && echo true || echo false)"
teardown

# --- Keep awake (ccs caffeine) --------------------------------------------
# The keep-awake tool is stubbed under both names ccs can reach for (caffeinate
# on Darwin, systemd-inhibit on Linux), so the same assertions hold on either CI
# runner. Every flag ccs passes is -x or --k=v, so the stub's shift loop lands
# exactly on `claude` — which is also why gnome-session-inhibit, the one form
# with a separate value word, is never reached here.
CAFF_DIR=""

caffeine_shims() {
    CAFF_DIR=$(mktemp -d)
    printf '#!/bin/sh\necho "CLAUDE_ARGV:$*"\nenv | grep -E "^ANTHROPIC_" || true\n' \
        > "$CAFF_DIR/claude"
    chmod +x "$CAFF_DIR/claude"
    for tool in caffeinate systemd-inhibit; do
        cat > "$CAFF_DIR/$tool" <<'SHIM'
#!/bin/sh
echo "CAFFEINE_ARGS:$*"
while :; do case "${1:-}" in -*) shift ;; *) break ;; esac; done
exec "$@"
SHIM
        chmod +x "$CAFF_DIR/$tool"
    done
}

# What ccs should hand the tool on this OS, per mode
case "$(uname -s 2>/dev/null || printf 'unknown')" in
    Darwin) CAFF_SYSTEM="CAFFEINE_ARGS:-ims "
            CAFF_DISPLAY="CAFFEINE_ARGS:-dims " ;;
    Linux)  CAFF_SYSTEM="CAFFEINE_ARGS:--what=sleep "
            CAFF_DISPLAY="CAFFEINE_ARGS:--what=sleep:idle " ;;
    *)      CAFF_SYSTEM="" CAFF_DISPLAY="" ;;
esac

# -- Caffeine: the persistent toggle --
printf '\033[1m[caffeine toggle]\033[0m\n'
setup
CFG="$TEST_CONFIG_DIR/.claude-provider/config"
out=$("$CCS" caffeine status)
assert_contains "caffeine is off by default" "Caffeine:  off" "$out"
"$CCS" caffeine on >/dev/null 2>&1
assert_contains "on writes caffeine=system" "caffeine=system" "$(cat "$CFG")"
out=$("$CCS" caffeine status)
assert_contains "status reports the system mode" "on (system" "$out"
"$CCS" caffeine on display >/dev/null 2>&1
assert_contains "on display writes caffeine=display" "caffeine=display" "$(cat "$CFG")"
"$CCS" caffeine off >/dev/null 2>&1
assert_contains "off writes caffeine=off" "caffeine=off" "$(cat "$CFG")"
assert_contains "status reports off again" "Caffeine:  off" "$("$CCS" caffeine status)"
assert_exit "invalid mode rejected" "1" "$CCS" caffeine on badmode
assert_exit "invalid subcommand rejected" "1" "$CCS" caffeine badsub
teardown

# -- Caffeine: what actually wraps the launch --
printf '\033[1m[caffeine launch wrapping]\033[0m\n'
setup
caffeine_shims
set_all_keys "sk-ant-test"
"$CCS" use anthropic >/dev/null 2>&1
out=$(PATH="$CAFF_DIR:$PATH" "$CCS" launch 2>/dev/null)
assert_not_contains "off launches with no wrapper" "CAFFEINE_ARGS" "$out"
out=$(PATH="$CAFF_DIR:$PATH" "$CCS" --caffeine 2>/dev/null)
assert_contains "--caffeine wraps the launch" "CAFFEINE_ARGS" "$out"
assert_contains "--caffeine never reaches claude" "CLAUDE_ARGV:" "$out"
assert_not_contains "claude gets no caffeine flag" "CLAUDE_ARGV:--caffeine" "$out"
assert_contains "provider env still reaches claude" "ANTHROPIC_API_KEY=sk-ant-test" "$out"
if [ -n "$CAFF_SYSTEM" ]; then
    assert_contains "system mode passes the right flags" "$CAFF_SYSTEM" "$out"
fi
out=$(PATH="$CAFF_DIR:$PATH" "$CCS" --caffeine --continue -p hi 2>/dev/null)
assert_contains "claude keeps its own arguments" "CLAUDE_ARGV:--continue -p hi" "$out"
out=$(PATH="$CAFF_DIR:$PATH" "$CCS" --caffeine=display 2>/dev/null)
if [ -n "$CAFF_DISPLAY" ]; then
    assert_contains "display mode passes the right flags" "$CAFF_DISPLAY" "$out"
fi
# The config is only consulted through parse_config, which load_state skips
# whenever an active state file exists — `ccs use` above wrote one.
"$CCS" caffeine on >/dev/null 2>&1
out=$(PATH="$CAFF_DIR:$PATH" "$CCS" launch 2>/dev/null)
assert_contains "config toggle survives an active state file" "CAFFEINE_ARGS" "$out"
out=$(PATH="$CAFF_DIR:$PATH" "$CCS" --no-caffeine 2>/dev/null)
assert_not_contains "--no-caffeine overrides the config" "CAFFEINE_ARGS" "$out"
out=$("$CCS" status)
assert_contains "ccs status shows the caffeine state" "Caffeine:  on" "$out"
# A third-party provider takes the other exec branch entirely
"$CCS" use zai >/dev/null 2>&1
out=$(PATH="$CAFF_DIR:$PATH" "$CCS" launch 2>/dev/null)
assert_contains "third-party launch is wrapped too" "CAFFEINE_ARGS" "$out"
assert_contains "third-party env still reaches claude" "ANTHROPIC_AUTH_TOKEN=sk-ant-test" "$out"
rm -rf "$CAFF_DIR"
teardown

# -- Caffeine: env cannot carry a sleep assertion --
printf '\033[1m[caffeine and ccs env]\033[0m\n'
setup
set_all_keys "sk-ant-test"
"$CCS" use anthropic >/dev/null 2>&1
"$CCS" caffeine on >/dev/null 2>&1
out=$("$CCS" env 2>/dev/null)
assert_not_contains "the note stays off stdout" "cannot keep a machine awake" "$out"
assert_contains "stdout is still just exports" "export ANTHROPIC_MODEL=" "$out"
err=$("$CCS" env 2>&1 >/dev/null)
assert_contains "the note goes to stderr" "cannot keep a machine awake" "$err"
"$CCS" caffeine off >/dev/null 2>&1
err=$("$CCS" env 2>&1 >/dev/null)
assert_not_contains "no note when caffeine is off" "cannot keep a machine awake" "$err"
teardown

# -- Caffeine: no keep-awake tool on this OS --
printf '\033[1m[caffeine without a tool]\033[0m\n'
setup
caffeine_shims
# uname is the only thing that picks the branch, and nothing else on the launch
# path calls it — shadow it to reach the "unsupported OS" arm on any runner.
cat > "$CAFF_DIR/uname" <<'SHIM'
#!/bin/sh
[ "${1:-}" = "-s" ] && { echo SunOS; exit 0; }
exec /usr/bin/uname "$@"
SHIM
chmod +x "$CAFF_DIR/uname"
set_all_keys "sk-ant-test"
"$CCS" use anthropic >/dev/null 2>&1
"$CCS" caffeine on >/dev/null 2>&1
out=$(PATH="$CAFF_DIR:$PATH" "$CCS" launch 2>&1)
assert_contains "a missing tool warns" "will not stay awake" "$out"
assert_contains "a missing tool still launches claude" "CLAUDE_ARGV:" "$out"
assert_not_contains "and wraps nothing" "CAFFEINE_ARGS" "$out"
rm -rf "$CAFF_DIR"
teardown

# -- Caffeine: the vanilla fallback is caffeinated too --
printf '\033[1m[caffeine vanilla fallback]\033[0m\n'
setup
caffeine_shims
# No API key anywhere → vanilla claude, which is about the machine either way
set_key _defaults provider anthropic
"$CCS" caffeine on >/dev/null 2>&1
out=$(PATH="$CAFF_DIR:$PATH" "$CCS" launch 2>&1)
assert_contains "vanilla fallback still warns" "vanilla" "$out"
assert_contains "vanilla fallback is wrapped" "CAFFEINE_ARGS" "$out"
assert_contains "vanilla claude still runs" "CLAUDE_ARGV:" "$out"
rm -rf "$CAFF_DIR"
teardown

# -- Caffeine: the native login is wrapped like any other provider --
# The whole point of the feature for a subscription user: keep awake without
# an API key, and without a single variable reaching claude.
printf '\033[1m[caffeine and the native login]\033[0m\n'
setup
caffeine_shims
"$CCS" use claude >/dev/null 2>&1
out=$(PATH="$CAFF_DIR:$PATH" "$CCS" launch 2>/dev/null)
assert_not_contains "off leaves the native launch unwrapped" "CAFFEINE_ARGS" "$out"
out=$(PATH="$CAFF_DIR:$PATH" "$CCS" --caffeine -p hi 2>/dev/null)
assert_contains "--caffeine wraps the native launch" "CAFFEINE_ARGS" "$out"
assert_contains "claude still runs with its arguments" "CLAUDE_ARGV:-p hi" "$out"
assert_not_contains "and still gets no provider env" "ANTHROPIC_" "$out"
if [ -n "$CAFF_SYSTEM" ]; then
    assert_contains "system mode passes the same flags" "$CAFF_SYSTEM" "$out"
fi
"$CCS" caffeine on >/dev/null 2>&1
out=$(PATH="$CAFF_DIR:$PATH" "$CCS" launch 2>/dev/null)
assert_contains "the config toggle reaches the native launch" "CAFFEINE_ARGS" "$out"
out=$(PATH="$CAFF_DIR:$PATH" "$CCS" --no-caffeine 2>/dev/null)
assert_not_contains "--no-caffeine still overrides it" "CAFFEINE_ARGS" "$out"
rm -rf "$CAFF_DIR"
teardown

# -- Caffeine: ccs only, claude untouched --
# The whole point of the sidecar contract: caffeine must leave ~/.claude
# exactly as it found it, and must never leak a flag into claude's argv.
printf '\033[1m[caffeine touches nothing of claude]\033[0m\n'
setup
caffeine_shims
mkdir -p "$TEST_CONFIG_DIR/.claude/agents"
printf '{"model":"opus"}\n' > "$TEST_CONFIG_DIR/.claude/settings.json"
printf '# global\n' > "$TEST_CONFIG_DIR/.claude/CLAUDE.md"
printf 'x\n' > "$TEST_CONFIG_DIR/.claude/agents/a.md"
before=$(find "$TEST_CONFIG_DIR/.claude" | sort)
before_sum=$(cat "$TEST_CONFIG_DIR/.claude/settings.json" "$TEST_CONFIG_DIR/.claude/CLAUDE.md")
set_all_keys "sk-ant-test"
"$CCS" use anthropic >/dev/null 2>&1
"$CCS" caffeine on >/dev/null 2>&1
"$CCS" caffeine on display >/dev/null 2>&1
"$CCS" caffeine status >/dev/null 2>&1
PATH="$CAFF_DIR:$PATH" "$CCS" launch >/dev/null 2>&1
PATH="$CAFF_DIR:$PATH" "$CCS" --caffeine >/dev/null 2>&1
"$CCS" caffeine off >/dev/null 2>&1
assert_eq "no file added or removed under ~/.claude" "$before" \
    "$(find "$TEST_CONFIG_DIR/.claude" | sort)"
assert_eq "settings.json and CLAUDE.md byte-identical" "$before_sum" \
    "$(cat "$TEST_CONFIG_DIR/.claude/settings.json" "$TEST_CONFIG_DIR/.claude/CLAUDE.md")"
assert_not_contains "no hook was installed" "hooks" "$(cat "$TEST_CONFIG_DIR/.claude/settings.json")"
# ...and the state it does write is one key in its own config
assert_contains "state lives in the ccs config" "caffeine=off" \
    "$(cat "$TEST_CONFIG_DIR/.claude-provider/config")"
out=$(PATH="$CAFF_DIR:$PATH" "$CCS" --caffeine --no-caffeine --caffeine=display -p hi 2>/dev/null)
assert_contains "claude sees only its own arguments" "CLAUDE_ARGV:-p hi" "$out"
rm -rf "$CAFF_DIR"
teardown

# -- Caffeine: platforms ccs cannot keep awake --
# Git Bash / MSYS / Cygwin report a Windows uname; WSL reports Linux but cannot
# reach the Windows host's power management. Both must degrade, never break.
printf '\033[1m[caffeine on unsupported platforms]\033[0m\n'
setup
caffeine_shims
set_all_keys "sk-ant-test"
"$CCS" use anthropic >/dev/null 2>&1
"$CCS" caffeine on >/dev/null 2>&1
for fake_os in MINGW64_NT-10.0-26100 CYGWIN_NT-10.0 FreeBSD; do
    cat > "$CAFF_DIR/uname" <<SHIM
#!/bin/sh
[ "\${1:-}" = "-s" ] && { echo $fake_os; exit 0; }
exec /usr/bin/uname "\$@"
SHIM
    chmod +x "$CAFF_DIR/uname"
    out=$(PATH="$CAFF_DIR:$PATH" "$CCS" launch 2>&1)
    assert_contains "$fake_os warns instead of wrapping" "will not stay awake" "$out"
    assert_contains "$fake_os still launches claude" "CLAUDE_ARGV:" "$out"
done
# WSL: uname says Linux, /proc/sys/kernel/osrelease gives it away
cat > "$CAFF_DIR/uname" <<'SHIM'
#!/bin/sh
[ "${1:-}" = "-s" ] && { echo Linux; exit 0; }
exec /usr/bin/uname "$@"
SHIM
chmod +x "$CAFF_DIR/uname"
printf '5.15.167.4-microsoft-standard-WSL2\n' > "$CAFF_DIR/osrelease"
out=$(PATH="$CAFF_DIR:$PATH" CCS_OSRELEASE="$CAFF_DIR/osrelease" "$CCS" launch 2>&1)
assert_contains "WSL says the Windows host is out of reach" "WSL cannot keep the Windows host awake" "$out"
assert_contains "WSL still launches claude" "CLAUDE_ARGV:" "$out"
assert_not_contains "WSL wraps nothing" "CAFFEINE_ARGS" "$out"
# A real Linux osrelease must not trip the WSL branch
printf '6.8.0-generic\n' > "$CAFF_DIR/osrelease"
out=$(PATH="$CAFF_DIR:$PATH" CCS_OSRELEASE="$CAFF_DIR/osrelease" "$CCS" launch 2>&1)
assert_not_contains "plain Linux is not mistaken for WSL" "WSL cannot" "$out"
assert_contains "plain Linux wraps normally" "CAFFEINE_ARGS:--what=sleep " "$out"
rm -rf "$CAFF_DIR"
teardown

# -- Caffeine: the gnome-session-inhibit fallback --
# Reached only when systemd-inhibit is absent, so the PATH is rebuilt from
# scratch with just the binaries ccs needs — same trick as [sync: git absent].
# Without this the fallback would be code that never runs anywhere.
printf '\033[1m[caffeine gnome fallback]\033[0m\n'
setup
set_all_keys "sk-ant-test"
"$CCS" use anthropic >/dev/null 2>&1
"$CCS" caffeine on >/dev/null 2>&1
NOSD_DIR=$(mktemp -d)
for b in sh sed awk grep find mkdir mktemp date cat cp rm mv ls chmod rmdir \
         head tail tr wc diff sort stat env dirname basename rev cut \
         touch sleep kill expr pgrep; do
    p=$(command -v "$b" 2>/dev/null) && ln -sf "$p" "$NOSD_DIR/$b"
done
REAL_UNAME=$(command -v uname)
cat > "$NOSD_DIR/uname" <<SHIM
#!/bin/sh
[ "\${1:-}" = "-s" ] && { echo Linux; exit 0; }
exec $REAL_UNAME "\$@"
SHIM
cat > "$NOSD_DIR/gnome-session-inhibit" <<'SHIM'
#!/bin/sh
echo "CAFFEINE_ARGS:$*"
while :; do case "${1:-}" in --inhibit|--reason) shift 2 ;; -*) shift ;; *) break ;; esac; done
exec "$@"
SHIM
printf '#!/bin/sh\necho "CLAUDE_ARGV:$*"\n' > "$NOSD_DIR/claude"
chmod +x "$NOSD_DIR/uname" "$NOSD_DIR/gnome-session-inhibit" "$NOSD_DIR/claude"
assert_eq "the stub PATH really has no systemd-inhibit" "false" \
    "$([ -e "$NOSD_DIR/systemd-inhibit" ] && echo true || echo false)"
assert_eq "and no caffeinate either" "false" \
    "$([ -e "$NOSD_DIR/caffeinate" ] && echo true || echo false)"
out=$(PATH="$NOSD_DIR" "$CCS" launch 2>&1)
assert_contains "falls back to gnome-session-inhibit" \
    "CAFFEINE_ARGS:--inhibit suspend --reason ccs-session" "$out"
assert_contains "and still runs claude" "CLAUDE_ARGV:" "$out"
out=$(PATH="$NOSD_DIR" "$CCS" --caffeine=display 2>&1)
assert_contains "display mode inhibits idle too" \
    "CAFFEINE_ARGS:--inhibit suspend:idle --reason ccs-session" "$out"
rm -rf "$NOSD_DIR"
teardown

# --- Sync helpers ---------------------------------------------------------
# The whole sync suite runs against a bare repo on disk reached over file://,
# so it never touches the network and never needs gh. git identity is written
# into the working copy by ccs itself, which is what makes this pass on a CI
# runner with no global git config.

CLAUDE_HOME=""
SYNC_REMOTE_URL=""

sync_setup() {
    setup
    CLAUDE_HOME="$TEST_CONFIG_DIR/.claude"
    SYNC_REMOTE_URL="file://$TEST_CONFIG_DIR/remote.git"
    git init --bare -q "$TEST_CONFIG_DIR/remote.git"
}

# A believable ~/.claude: some config worth keeping, and a pile of things that
# must never leave the machine.
make_claude_home() {
    mkdir -p "$CLAUDE_HOME/skills/demo" "$CLAUDE_HOME/commands" \
             "$CLAUDE_HOME/projects/p1" "$CLAUDE_HOME/plugins"
    printf '# global rules\n' > "$CLAUDE_HOME/CLAUDE.md"
    printf '{"model":"opus"}\n' > "$CLAUDE_HOME/settings.json"
    printf 'name: demo\n' > "$CLAUDE_HOME/skills/demo/SKILL.md"
    printf 'run it\n' > "$CLAUDE_HOME/commands/go.md"
    printf '{"plugins":[]}\n' > "$CLAUDE_HOME/plugins/installed_plugins.json"
    printf 'private transcript\n' > "$CLAUDE_HOME/projects/p1/session.jsonl"
    printf 'private history\n' > "$CLAUDE_HOME/history.jsonl"
    printf 'credentials\n' > "$CLAUDE_HOME/.credentials.json"
    printf '{"local":true}\n' > "$CLAUDE_HOME/settings.local.json"
}

sync_init_repo() {
    "$CCS" sync init --repo "$SYNC_REMOTE_URL" >/dev/null 2>&1
}

# Clone the remote and list what actually landed there
remote_files() {
    rm -rf "$TEST_CONFIG_DIR/verify"
    git clone -q "$SYNC_REMOTE_URL" "$TEST_CONFIG_DIR/verify" 2>/dev/null
    ( cd "$TEST_CONFIG_DIR/verify" && find . -path ./.git -prune -o -type f -print | sort )
}

# -- Reserved sections are not providers --
printf '\033[1m[sync: reserved sections]\033[0m\n'
setup
out=$("$CCS" list)
assert_not_contains "list hides the reserved _sync section" "_sync" "$out"
assert_exit "use _sync is rejected" "1" "$CCS" use _sync
out=$("$CCS" sync status)
assert_contains "sync status reads [_sync]" "not configured" "$out"
teardown

# -- init + push: the allow-list is respected --
printf '\033[1m[sync: push allow-list]\033[0m\n'
sync_setup
make_claude_home
out=$(sync_init_repo && "$CCS" sync push 2>&1)
assert_contains "push reports the backup" "Backed up" "$out"
files=$(remote_files)
assert_contains "remote has CLAUDE.md" "./CLAUDE.md" "$files"
assert_contains "remote has settings.json" "./settings.json" "$files"
assert_contains "remote has skills" "./skills/demo/SKILL.md" "$files"
assert_contains "remote has commands" "./commands/go.md" "$files"
assert_contains "remote has the plugin manifest" "./plugins/installed_plugins.json" "$files"
assert_contains "remote carries a manifest" "./.ccs-sync" "$files"
assert_not_contains "remote has no transcripts" "projects" "$files"
assert_not_contains "remote has no history" "history.jsonl" "$files"
assert_not_contains "remote has no credentials" "credentials" "$files"
assert_not_contains "remote has no machine-local settings" "settings.local.json" "$files"
out=$("$CCS" sync push 2>&1)
assert_contains "a second push is a no-op" "Already up to date" "$out"
teardown

# -- Symlinked skills are materialised, not linked --
printf '\033[1m[sync: symlinks]\033[0m\n'
sync_setup
make_claude_home
mkdir -p "$TEST_CONFIG_DIR/external"
printf 'linked skill\n' > "$TEST_CONFIG_DIR/external/SKILL.md"
ln -s "$TEST_CONFIG_DIR/external" "$CLAUDE_HOME/skills/linked"
sync_init_repo
"$CCS" sync push >/dev/null 2>&1
remote_files >/dev/null
assert_eq "symlinked skill is copied by content" "linked skill" \
    "$(cat "$TEST_CONFIG_DIR/verify/skills/linked/SKILL.md" 2>/dev/null)"
assert_eq "and lands as a real file" "false" \
    "$([ -L "$TEST_CONFIG_DIR/verify/skills/linked" ] && echo true || echo false)"
teardown

# -- settings.json is made portable, and ccs's own hooks stay home --
printf '\033[1m[sync: portable settings.json]\033[0m\n'
sync_setup
make_claude_home
"$CCS" notify on ghostty >/dev/null 2>&1
printf '{"statusLine":{"command":"%s/bin/line"}}\n' "$TEST_CONFIG_DIR" > "$CLAUDE_HOME/settings.json"
"$CCS" notify on ghostty >/dev/null 2>&1
sync_init_repo
"$CCS" sync push >/dev/null 2>&1
remote_files >/dev/null
remote_settings=$(cat "$TEST_CONFIG_DIR/verify/settings.json")
assert_contains "remote settings.json uses the HOME placeholder" "__CCS_HOME__/bin/line" "$remote_settings"
assert_not_contains "remote settings.json leaks no absolute HOME" "$TEST_CONFIG_DIR/bin" "$remote_settings"
assert_not_contains "remote settings.json drops the ccs hooks" "notify-stop.sh" "$remote_settings"
assert_exit "remote settings.json is valid JSON" "0" jq empty "$TEST_CONFIG_DIR/verify/settings.json"
"$CCS" sync pull >/dev/null 2>&1
local_settings=$(cat "$CLAUDE_HOME/settings.json")
assert_contains "pull restores the real HOME" "$TEST_CONFIG_DIR/bin/line" "$local_settings"
assert_not_contains "pull leaves no placeholder behind" "__CCS_HOME__" "$local_settings"
assert_contains "pull re-attaches the local ccs hooks" "notify-stop.sh" "$local_settings"
teardown

# -- The secret scan blocks a push --
printf '\033[1m[sync: secret scan]\033[0m\n'
sync_setup
make_claude_home
sync_init_repo
# Assembled at runtime so the literal never sits in this file
printf 'key: %s%s\n' 'sk-ant-' 'api03-AAAAAAAAAAAAAAAAAAAAAAAAAAAA' \
    > "$CLAUDE_HOME/skills/demo/leak.md"
assert_exit "push refuses a credential" "1" "$CCS" sync push
err=$("$CCS" sync push 2>&1 >/dev/null || true)
assert_contains "the offending file is named" "leak.md" "$err"
assert_exit "push --force overrides the scan" "0" "$CCS" sync push --force
teardown

# -- Restore: mirror by default, additive on request --
printf '\033[1m[sync: pull mirror vs additive]\033[0m\n'
sync_setup
make_claude_home
sync_init_repo
"$CCS" sync push >/dev/null 2>&1
mkdir -p "$CLAUDE_HOME/skills/only-here"
printf 'local only\n' > "$CLAUDE_HOME/skills/only-here/SKILL.md"
printf 'edited locally\n' > "$CLAUDE_HOME/CLAUDE.md"
out=$("$CCS" sync pull --dry-run 2>&1)
assert_contains "dry-run flags the divergence" "skills" "$out"
assert_contains "dry-run says nothing was touched" "was not touched" "$out"
assert_eq "dry-run really changed nothing" "edited locally" "$(cat "$CLAUDE_HOME/CLAUDE.md")"
"$CCS" sync pull >/dev/null 2>&1
assert_eq "mirror restores the remote file" "# global rules" "$(cat "$CLAUDE_HOME/CLAUDE.md")"
assert_eq "mirror drops what the remote does not have" "false" \
    "$([ -e "$CLAUDE_HOME/skills/only-here" ] && echo true || echo false)"
backup=$(find "$TEST_CONFIG_DIR/.claude-provider/sync-backup" -mindepth 1 -maxdepth 1 -type d | head -1)
assert_eq "pull snapshots ~/.claude first" "edited locally" \
    "$(cat "$backup/CLAUDE.md" 2>/dev/null)"
assert_eq "the snapshot keeps the pruned skill" "local only" \
    "$(cat "$backup/skills/only-here/SKILL.md" 2>/dev/null)"
mkdir -p "$CLAUDE_HOME/skills/kept"
printf 'keep me\n' > "$CLAUDE_HOME/skills/kept/SKILL.md"
"$CCS" sync pull --additive >/dev/null 2>&1
assert_eq "additive keeps local-only files" "keep me" \
    "$(cat "$CLAUDE_HOME/skills/kept/SKILL.md" 2>/dev/null)"
teardown

# -- A gist stores a flattened tree, and restores it nested --
printf '\033[1m[sync: gist flattening]\033[0m\n'
sync_setup
make_claude_home
"$CCS" sync init --gist "$SYNC_REMOTE_URL" >/dev/null 2>&1
out=$("$CCS" sync status)
assert_contains "gist storage is recorded" "gist" "$out"
"$CCS" sync push >/dev/null 2>&1
files=$(remote_files)
assert_contains "gist encodes nested paths" "./skills%2Fdemo%2FSKILL.md" "$files"
assert_contains "gist keeps top-level files as they are" "./CLAUDE.md" "$files"
rm -rf "$CLAUDE_HOME/skills" "$CLAUDE_HOME/commands"
"$CCS" sync pull >/dev/null 2>&1
assert_eq "gist pull rebuilds the tree" "name: demo" \
    "$(cat "$CLAUDE_HOME/skills/demo/SKILL.md" 2>/dev/null)"
assert_eq "no encoded name survives the pull" "false" \
    "$([ -e "$CLAUDE_HOME/skills%2Fdemo%2FSKILL.md" ] && echo true || echo false)"
teardown

# -- include_ccs strips keys on the way out and never clobbers one coming in --
printf '\033[1m[sync: ccs config]\033[0m\n'
sync_setup
make_claude_home
set_all_keys "test-key-123"
set_key _sync include_ccs true
sync_init_repo
"$CCS" sync push >/dev/null 2>&1
remote_files >/dev/null
remote_cfg=$(cat "$TEST_CONFIG_DIR/verify/ccs/config")
assert_contains "the ccs config is published" "[zai]" "$remote_cfg"
assert_not_contains "with no API key in it" "test-key-123" "$remote_cfg"
assert_contains "keys are blanked, not dropped" "api_key=" "$remote_cfg"
assert_not_contains "and without the machine's own [_sync]" "remote=file://" "$remote_cfg"
set_key zai model "glm-from-remote"
"$CCS" sync push >/dev/null 2>&1
set_key zai model "glm-local"
"$CCS" sync pull >/dev/null 2>&1
cfg=$(cat "$TEST_CONFIG_DIR/.claude-provider/config")
assert_contains "pull merges the remote model" "model=glm-from-remote" "$cfg"
assert_contains "pull keeps the local API key" "api_key=test-key-123" "$cfg"
assert_contains "pull does not adopt a remote sync target" "remote=$TEST_CONFIG_DIR/remote.git" \
    "$(sed -n 's|^remote=file://|remote=|p' "$TEST_CONFIG_DIR/.claude-provider/config")"
teardown

# -- import brings someone else's config in, without adopting their remote --
printf '\033[1m[sync: import]\033[0m\n'
sync_setup
make_claude_home
sync_init_repo
"$CCS" sync push >/dev/null 2>&1
rm -rf "$TEST_CONFIG_DIR/.claude-provider" "$CLAUDE_HOME"
mkdir -p "$CLAUDE_HOME"
"$CCS" help >/dev/null 2>&1
assert_exit "import without --yes on a pipe is refused" "1" "$CCS" sync import "$SYNC_REMOTE_URL"
out=$("$CCS" sync import "$SYNC_REMOTE_URL" --yes 2>&1)
assert_contains "import reports where it read from" "Importing from" "$out"
assert_eq "import restores CLAUDE.md" "# global rules" "$(cat "$CLAUDE_HOME/CLAUDE.md" 2>/dev/null)"
assert_eq "import restores skills" "name: demo" "$(cat "$CLAUDE_HOME/skills/demo/SKILL.md" 2>/dev/null)"
assert_eq "import brings no transcripts" "false" \
    "$([ -e "$CLAUDE_HOME/projects" ] && echo true || echo false)"
out=$("$CCS" sync status)
assert_contains "import does not adopt the remote" "not configured" "$out"
"$CCS" sync import "$SYNC_REMOTE_URL" --yes --adopt >/dev/null 2>&1
out=$("$CCS" sync status)
assert_contains "--adopt does configure it" "remote.git" "$out"
teardown

# -- Session hooks live alongside the notify hooks --
printf '\033[1m[sync: session hooks]\033[0m\n'
sync_setup
make_claude_home
SETTINGS="$CLAUDE_HOME/settings.json"
sync_init_repo
"$CCS" notify on >/dev/null 2>&1
"$CCS" sync hooks on >/dev/null 2>&1
assert_eq "pull hook created" "true" \
    "$([ -x "$TEST_CONFIG_DIR/.claude-provider/hooks/sync-pull.sh" ] && echo true || echo false)"
assert_exit "settings.json stays valid JSON" "0" jq empty "$SETTINGS"
assert_eq "SessionStart is hooked" "1" "$(jq '.hooks.SessionStart | length' "$SETTINGS")"
assert_eq "SessionEnd is hooked" "1" "$(jq '.hooks.SessionEnd | length' "$SETTINGS")"
assert_eq "notify's Stop hook is untouched" "1" "$(jq '.hooks.Stop | length' "$SETTINGS")"
# The hook has to run silently — Claude Code reads hook stdout
out=$(printf '{}' | "$TEST_CONFIG_DIR/.claude-provider/hooks/sync-push.sh" 2>&1)
assert_eq "the SessionEnd hook prints nothing" "" "$out"
assert_contains "and actually pushed" "./CLAUDE.md" "$(remote_files)"
set_key _sync remote "file://$TEST_CONFIG_DIR/gone.git"
out=$(printf '{}' | "$TEST_CONFIG_DIR/.claude-provider/hooks/sync-pull.sh" 2>&1)
assert_eq "a hook against a dead remote stays silent" "" "$out"
assert_eq "and leaves ~/.claude alone" "# global rules" "$(cat "$CLAUDE_HOME/CLAUDE.md")"
set_key _sync remote "$SYNC_REMOTE_URL"
"$CCS" sync hooks on >/dev/null 2>&1
assert_eq "installing twice does not duplicate" "1" "$(jq '.hooks.SessionStart | length' "$SETTINGS")"
"$CCS" notify off >/dev/null 2>&1
assert_eq "notify off leaves the sync hooks alone" "1" "$(jq '.hooks.SessionStart | length' "$SETTINGS")"
assert_eq "notify off still removes its own" "null" "$(jq -r '.hooks.Stop' "$SETTINGS")"
assert_eq "notify off keeps the sync scripts" "true" \
    "$([ -x "$TEST_CONFIG_DIR/.claude-provider/hooks/sync-pull.sh" ] && echo true || echo false)"
"$CCS" sync hooks off >/dev/null 2>&1
assert_eq "sync hooks off clears SessionStart" "null" "$(jq -r '.hooks.SessionStart' "$SETTINGS")"
assert_eq "and removes the hooks dir once empty" "false" \
    "$([ -d "$TEST_CONFIG_DIR/.claude-provider/hooks" ] && echo true || echo false)"
teardown

# -- purge detaches both hook families --
printf '\033[1m[sync: purge detaches session hooks]\033[0m\n'
sync_setup
make_claude_home
SETTINGS="$CLAUDE_HOME/settings.json"
sync_init_repo
"$CCS" notify on >/dev/null 2>&1
"$CCS" sync hooks on >/dev/null 2>&1
"$CCS" purge >/dev/null 2>&1
assert_not_contains "purge removes every ccs hook reference" "claude-provider" "$(cat "$SETTINGS")"
assert_exit "settings still valid JSON after purge" "0" jq empty "$SETTINGS"
teardown

# -- Auto sync never blocks a launch --
printf '\033[1m[sync: auto never blocks the launch]\033[0m\n'
sync_setup
make_claude_home
SHIM_DIR=$(mktemp -d)
printf '#!/bin/sh\necho CLAUDE_RAN\n' > "$SHIM_DIR/claude"
chmod +x "$SHIM_DIR/claude"
sync_init_repo
"$CCS" sync auto on >/dev/null 2>&1
set_all_keys "test-key-123"
"$CCS" use zai >/dev/null 2>&1
out=$(PATH="$SHIM_DIR:$PATH" "$CCS" launch 2>&1)
assert_contains "a working auto sync still launches claude" "CLAUDE_RAN" "$out"
files=$(remote_files)
assert_contains "and the launch pushed the config" "./CLAUDE.md" "$files"
# Now point at a remote that cannot answer
set_key _sync remote "file://$TEST_CONFIG_DIR/gone.git"
out=$(PATH="$SHIM_DIR:$PATH" "$CCS" launch 2>&1)
assert_contains "an unreachable remote still launches claude" "CLAUDE_RAN" "$out"
assert_contains "and says why" "config sync failed" "$out"
"$CCS" sync auto off >/dev/null 2>&1
rm -rf "$SHIM_DIR"
teardown

# -- sync off forgets the remote and touches nothing else --
printf '\033[1m[sync: off]\033[0m\n'
sync_setup
make_claude_home
sync_init_repo
"$CCS" sync push >/dev/null 2>&1
"$CCS" sync off >/dev/null 2>&1
out=$("$CCS" sync status)
assert_contains "off forgets the remote" "not configured" "$out"
assert_eq "off leaves ~/.claude alone" "# global rules" "$(cat "$CLAUDE_HOME/CLAUDE.md")"
assert_eq "off drops the working copy" "false" \
    "$([ -d "$TEST_CONFIG_DIR/.claude-provider/sync" ] && echo true || echo false)"
assert_exit "push without a remote explains itself" "1" "$CCS" sync push
teardown

# -- Bad input --
printf '\033[1m[sync: bad input]\033[0m\n'
sync_setup
assert_exit "unknown subcommand rejected" "1" "$CCS" sync bogus
assert_exit "unknown push flag rejected" "1" "$CCS" sync push --nope
assert_exit "auto needs on or off" "1" "$CCS" sync auto maybe
assert_exit "hooks needs on or off" "1" "$CCS" sync hooks maybe
assert_exit "init needs a target" "1" "$CCS" sync init
assert_exit "init rejects an unreachable remote" "1" "$CCS" sync init --repo "file://$TEST_CONFIG_DIR/nope.git"
assert_exit "import needs a source" "1" "$CCS" sync import
teardown

# -- git is a soft dependency: absent, only sync stops working --
printf '\033[1m[sync: git absent]\033[0m\n'
sync_setup
make_claude_home
NOGIT_DIR=$(mktemp -d)
for b in sh sed awk grep tar find mkdir mktemp date cat cp rm mv ls chmod rmdir \
         head tail tr wc uname diff sort stat env dirname basename rev cut jq \
         touch sleep kill expr; do
    p=$(command -v "$b" 2>/dev/null) && ln -sf "$p" "$NOGIT_DIR/$b"
done
assert_eq "the stub PATH really has no git" "false" \
    "$([ -e "$NOGIT_DIR/git" ] && echo true || echo false)"
err=$(PATH="$NOGIT_DIR" "$CCS" sync push 2>&1 || true)
assert_contains "sync push says git is required" "git is required" "$err"
SHIM_DIR=$(mktemp -d)
printf '#!/bin/sh\necho CLAUDE_RAN\n' > "$SHIM_DIR/claude"
chmod +x "$SHIM_DIR/claude"
set_all_keys "test-key-123"
PATH="$NOGIT_DIR" "$CCS" use zai >/dev/null 2>&1
out=$(PATH="$SHIM_DIR:$NOGIT_DIR" "$CCS" launch 2>&1)
assert_contains "the rest of ccs still works without git" "CLAUDE_RAN" "$out"
rm -rf "$NOGIT_DIR" "$SHIM_DIR"
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

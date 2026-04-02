#!/bin/sh
# ccs installer
set -eu

PREFIX="${PREFIX:-/usr/local}"
BIN_DIR="${PREFIX}/bin"
CONFIG_DIR="${HOME}/.claude-provider"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

printf 'Installing ccs...\n'

# 1. Install binary
if [ ! -d "$BIN_DIR" ]; then
    printf 'Creating %s...\n' "$BIN_DIR"
    mkdir -p "$BIN_DIR"
fi

cp "${SCRIPT_DIR}/ccs" "${BIN_DIR}/ccs"
chmod 755 "${BIN_DIR}/ccs"
printf '  Installed %s/ccs\n' "$BIN_DIR"

# 2. Create config directory
mkdir -p "$CONFIG_DIR"
chmod 700 "$CONFIG_DIR"

# 3. Copy config template if no config exists
if [ ! -f "${CONFIG_DIR}/config" ]; then
    cp "${SCRIPT_DIR}/config.template" "${CONFIG_DIR}/config"
    chmod 600 "${CONFIG_DIR}/config"
    printf '  Created %s/config\n' "$CONFIG_DIR"
else
    printf '  Config already exists at %s/config (not overwritten)\n' "$CONFIG_DIR"
fi

printf '\nDone!\n\n'
printf 'Next steps:\n'
printf '  1. Add your API keys:  ccs config\n'
printf '  2. Switch provider:    ccs use <provider>\n'
printf '  3. Launch claude:      ccs launch\n'
printf '\n'
printf 'Optional shell integration (add to ~/.zshrc or ~/.bashrc):\n'
printf '\n'
printf '  ccs() {\n'
printf '      if [ "${1:-}" = "use" ] || [ "${1:-}" = "default" ]; then\n'
printf '          command ccs "$@" && eval "$(command ccs env)"\n'
printf '      else\n'
printf '          command ccs "$@"\n'
printf '      fi\n'
printf '  }\n'
printf '\n'

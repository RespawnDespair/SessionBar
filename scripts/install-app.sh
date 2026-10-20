#!/bin/zsh
# Builds, installs to /Applications, wires up the Claude Code hooks and starts the app.
set -euo pipefail

ROOT="${0:A:h:h}"
INSTALL_DIR="${SESSIONBAR_INSTALL_DIR:-/Applications}"
INSTALLED="$INSTALL_DIR/SessionBar.app"

"$ROOT/scripts/build-app.sh"
pkill -x SessionBar 2>/dev/null || true
if [[ -w "$INSTALL_DIR" ]]; then
    ditto "$ROOT/.build/SessionBar.app" "$INSTALLED"
else
    sudo ditto "$ROOT/.build/SessionBar.app" "$INSTALLED"
fi

# Hooks point at the installed binary, so install them from there.
"$INSTALLED/Contents/MacOS/SessionBar" --install-hooks
"$INSTALLED/Contents/MacOS/SessionBar" --launch-at-login on || true
open "$INSTALLED"
echo "Installed: $INSTALLED"

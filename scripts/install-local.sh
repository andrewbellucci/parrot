#!/usr/bin/env bash

# Build the current checkout, install it over the global Parrot binary, and
# stop a loaded LaunchAgent so Accessibility can be re-granted safely.

set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
INSTALL_DIR=${PARROT_INSTALL_DIR:-/usr/local/bin}
TARGET="$INSTALL_DIR/parrot"
BACKUP_DIR=${PARROT_BACKUP_DIR:-"$HOME/Library/Application Support/parrot/backups"}
LABEL=com.digimata.parrot
DOMAIN="gui/$(id -u)"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
AGENT_WAS_LOADED=0
RESTART_PENDING=0

restore_agent_on_error() {
    local exit_code=$?
    trap - EXIT
    if [ "$exit_code" -ne 0 ] && [ "$RESTART_PENDING" -eq 1 ] && [ -f "$PLIST" ]; then
        echo "→ install failed; restarting the previous LaunchAgent" >&2
        launchctl bootstrap "$DOMAIN" "$PLIST" >/dev/null 2>&1 || true
    fi
    exit "$exit_code"
}
trap restore_agent_on_error EXIT

echo "→ building release binary"
swift build --package-path "$REPO_DIR" -c release
BUILD_DIR=$(swift build --package-path "$REPO_DIR" -c release --show-bin-path)
SOURCE="$BUILD_DIR/parrot"

if [ ! -x "$SOURCE" ]; then
    echo "release binary not found at $SOURCE" >&2
    exit 1
fi

if launchctl print "$DOMAIN/$LABEL" >/dev/null 2>&1; then
    AGENT_WAS_LOADED=1
    RESTART_PENDING=1
    echo "→ stopping LaunchAgent"
    launchctl bootout "$DOMAIN" "$PLIST"
fi

if pgrep -x parrot >/dev/null 2>&1; then
    echo "another Parrot process is still running; stop it and retry" >&2
    exit 1
fi

if [ -f "$TARGET" ]; then
    mkdir -p "$BACKUP_DIR"
    BACKUP="$BACKUP_DIR/parrot-$(date +%Y%m%d-%H%M%S)"
    cp -p "$TARGET" "$BACKUP"
    echo "→ backed up current binary to $BACKUP"
fi

echo "→ installing $TARGET"
if [ -f "$TARGET" ] && [ -w "$TARGET" ]; then
    cp "$SOURCE" "$TARGET"
    chmod 755 "$TARGET"
elif [ -w "$INSTALL_DIR" ]; then
    install -m 755 "$SOURCE" "$TARGET"
else
    echo "  administrator access is required for $INSTALL_DIR"
    sudo mkdir -p "$INSTALL_DIR"
    sudo install -m 755 "$SOURCE" "$TARGET"
fi

if [ "$AGENT_WAS_LOADED" -eq 1 ]; then
    RESTART_PENDING=0
    echo "→ LaunchAgent left stopped for the Accessibility re-grant"
else
    echo "→ LaunchAgent was not loaded; start Parrot manually when ready"
fi

echo "✓ installed local release at $TARGET"
echo "  local builds are ad-hoc signed; re-add $TARGET under:"
echo "  System Settings → Privacy & Security → Accessibility"
echo "  then run: $TARGET restart"

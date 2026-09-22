#!/usr/bin/env bash
#
# Puts the command-line tool on the PATH and installs the agent skill that
# teaches Claude Code (or any agent with a skill system) to use it.
#
# The tool ships inside the app, at Contents/Helpers/invoices, so there is
# nothing to build: this links it from a directory on the PATH. The link
# points into the bundle, which is what keeps the tool current — a Sparkle
# update replaces the binary behind it along with the app. Install the app
# first (Scripts/install-release.sh, or the disk image).
#
# Usage: Scripts/install-cli.sh [bin-directory]   (default /usr/local/bin)
#        INVOICES_APP=/path/to/Invoices.app names another copy of the app.

set -euo pipefail

APP="${INVOICES_APP:-/Applications/Invoices.app}"
HELPER="$APP/Contents/Helpers/invoices"
BIN_DIR="${1:-/usr/local/bin}"

if [ ! -x "$HELPER" ]; then
  echo "No tool at $HELPER — install the app first (Scripts/install-release.sh, or the disk image)." >&2
  exit 1
fi

# A copy installed from the disk image carries the quarantine flag, and
# Gatekeeper judges a helper run from Terminal on its own, not by the
# "Open Anyway" already given to the app.
xattr -d com.apple.quarantine "$HELPER" 2>/dev/null || true

if [ -w "$BIN_DIR" ]; then
  ln -sfn "$HELPER" "$BIN_DIR/invoices"
else
  echo "$BIN_DIR is not writable; linking with sudo."
  sudo mkdir -p "$BIN_DIR"
  sudo ln -sfn "$HELPER" "$BIN_DIR/invoices"
fi
echo "Linked $BIN_DIR/invoices -> $HELPER"

# The skill, as the installed tool prints it, so it matches the binary.
# Claude Code reads personal skills from ~/.claude/skills/<name>/SKILL.md.
SKILL_DIR="$HOME/.claude/skills/invoices"
mkdir -p "$SKILL_DIR"
"$HELPER" skill > "$SKILL_DIR/SKILL.md"
echo "Wrote $SKILL_DIR/SKILL.md"

if ! command -v invoices >/dev/null 2>&1; then
  echo "Note: $BIN_DIR is not on your PATH; add it, or the agent will not find the tool."
fi

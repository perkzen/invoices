#!/usr/bin/env bash
#
# Builds the command-line tool and installs it as `invoices` on the PATH, and
# installs the agent skill that teaches Claude Code (or any agent with a
# skill system) to use it. The tool opens the store of the installed app —
# run Scripts/install-release.sh first — and takes the invoice's Slovenian
# wording from that app, so it has to be there.
#
# Usage: Scripts/install-cli.sh [bin-directory]   (default /usr/local/bin)

set -euo pipefail

cd "$(dirname "$0")/.."

BIN_DIR="${1:-/usr/local/bin}"
DERIVED_DATA="build"
BUILT_TOOL="$DERIVED_DATA/Build/Products/Release/invoices"

xcodegen generate

xcodebuild \
  -project Invoices.xcodeproj \
  -scheme InvoicesCLI \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA" \
  build

if [ -w "$BIN_DIR" ] || { [ ! -e "$BIN_DIR" ] && mkdir -p "$BIN_DIR" 2>/dev/null; }; then
  install -m 755 "$BUILT_TOOL" "$BIN_DIR/invoices"
else
  echo "$BIN_DIR is not writable; installing with sudo."
  sudo install -d "$BIN_DIR"
  sudo install -m 755 "$BUILT_TOOL" "$BIN_DIR/invoices"
fi
echo "Installed $BIN_DIR/invoices"

# The skill, linked rather than copied, so it follows the checkout. Claude
# Code reads personal skills from ~/.claude/skills/<name>/SKILL.md.
SKILLS_DIR="$HOME/.claude/skills"
mkdir -p "$SKILLS_DIR"
ln -sfn "$PWD/skills/invoices" "$SKILLS_DIR/invoices"
echo "Linked $SKILLS_DIR/invoices -> $PWD/skills/invoices"

if ! command -v invoices >/dev/null 2>&1; then
  echo "Note: $BIN_DIR is not on your PATH; add it, or the agent will not find the tool."
fi

#!/usr/bin/env bash
#
# Packages a built Invoices.app as the disk image a release publishes.
#
# Usage: Scripts/make-dmg.sh <path-to-Invoices.app> <version> [output.dmg]
#
# The layout lives in Scripts/dmg-settings.py; this only feeds it the app and
# names the volume. Both the volume name and the file name are part of the
# release contract — the appcast's enclosure URL is built from the file name,
# and Sparkle downloads exactly that.

set -euo pipefail

if [ $# -lt 2 ]; then
  echo "usage: $0 <path-to-Invoices.app> <version> [output.dmg]" >&2
  exit 64
fi

APP="$1"
VERSION="$2"
OUTPUT="${3:-Invoices-$VERSION.dmg}"
SETTINGS="$(cd "$(dirname "$0")" && pwd)/dmg-settings.py"

if [ ! -d "$APP" ]; then
  echo "$0: no app bundle at $APP" >&2
  exit 66
fi

# dmgbuild resolves nothing relative to the settings file, and the workflow
# hands this a path relative to the checkout — absolutize once, here.
APP="$(cd "$(dirname "$APP")" && pwd)/$(basename "$APP")"

# dmgbuild refuses to overwrite, and a stale image from a previous attempt is
# never the one you want to ship.
rm -f "$OUTPUT"

dmgbuild -s "$SETTINGS" -D app="$APP" "Invoices $VERSION" "$OUTPUT"

echo "Wrote $OUTPUT"

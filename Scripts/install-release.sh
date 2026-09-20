#!/usr/bin/env bash
#
# Builds the Release configuration and installs it as /Applications/Invoices.app
# — the copy you actually keep your invoices in. The Debug build that Xcode
# runs is a separate app (com.domenperko.Invoices.dev, shown as "Invoices Dev")
# with its own sandbox container, so the two never share data.
#
# Usage: Scripts/install-release.sh [destination-directory]   (default /Applications)

set -euo pipefail

cd "$(dirname "$0")/.."

DESTINATION="${1:-/Applications}"
# One derived-data path for every command-line build. Ad-hoc paths are what
# scattered nine copies of this app across the disk the first time round.
DERIVED_DATA="build"
BUILT_APP="$DERIVED_DATA/Build/Products/Release/Invoices.app"

xcodegen generate

xcodebuild \
  -project Invoices.xcodeproj \
  -scheme Invoices \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA" \
  build

# ditto merges into an existing bundle rather than replacing it, which leaves
# files from the previous version behind — so clear the target first.
rm -rf "$DESTINATION/Invoices.app"
ditto "$BUILT_APP" "$DESTINATION/Invoices.app"

# xcodebuild registers whatever it builds with Launch Services, so the copy in
# the build tree would show up in Spotlight beside the installed one under the
# same name. Drop it: the installed app is the only Release build that matters.
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
"$LSREGISTER" -u "$BUILT_APP" 2>/dev/null || true
rm -rf "$(dirname "$BUILT_APP")"
"$LSREGISTER" -f "$DESTINATION/Invoices.app"

echo "Installed $DESTINATION/Invoices.app"

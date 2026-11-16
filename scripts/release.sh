#!/usr/bin/env bash
# Builds both downloads into build/release:
#   DynamicIsland-Notch.zip    for MacBooks with a notch
#   DynamicIsland-NoNotch.zip  for Macs without one (floating pill)
set -euo pipefail
cd "$(dirname "$0")/.."
rm -rf build/release
for variant in notch pill; do
  name="Notch"; [ "$variant" = "pill" ] && name="NoNotch"
  VARIANT="$variant" OUT_DIR="build/release/$name" ./scripts/build-app.sh
  ditto -c -k --keepParent "build/release/$name/Dynamic Island.app" "build/release/DynamicIsland-$name.zip"
done
ls -lh build/release/*.zip

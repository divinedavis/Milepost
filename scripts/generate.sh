#!/usr/bin/env bash
# Regenerate Milepost.xcodeproj from project.yml. Run after adding files.
# Never hand-edit project.pbxproj.
set -euo pipefail
cd "$(dirname "$0")/.."
find . -maxdepth 1 -name "Milepost [0-9]*.xcodeproj" -exec rm -rf {} + 2>/dev/null || true
# --use-cache: skipped when project.yml and every file path are unchanged
# since the last generate (the cache lives in ~/.xcodegen). A missing
# xcodeproj always regenerates.
if [[ -d Milepost.xcodeproj ]]; then xcodegen generate --use-cache; else xcodegen generate; fi
# Package versions are pinned by the committed Package.resolved (2026-10-24);
# the generated project is gitignored, so it gets a copy every time.
mkdir -p Milepost.xcodeproj/project.xcworkspace/xcshareddata/swiftpm
cp Package.resolved Milepost.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
echo "regenerated Milepost.xcodeproj"

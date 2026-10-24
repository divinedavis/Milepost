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
echo "regenerated Milepost.xcodeproj"

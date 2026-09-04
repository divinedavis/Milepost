#!/usr/bin/env bash
# Regenerate Milepost.xcodeproj from project.yml. Run after adding files.
# Never hand-edit project.pbxproj.
set -euo pipefail
cd "$(dirname "$0")/.."
find . -maxdepth 1 -name "Milepost [0-9]*.xcodeproj" -exec rm -rf {} + 2>/dev/null || true
xcodegen generate
echo "regenerated Milepost.xcodeproj"

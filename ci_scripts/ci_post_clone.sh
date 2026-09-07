#!/bin/sh
set -e

# Larpnet.xcodeproj is generated from project.yml and is gitignored (see
# .gitignore), so Xcode Cloud's checkout doesn't have it. Regenerate it here
# before the archive/build/test action runs.
brew install xcodegen

cd "$CI_PRIMARY_REPOSITORY_PATH"
xcodegen generate

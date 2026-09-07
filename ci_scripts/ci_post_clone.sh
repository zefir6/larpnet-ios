#!/bin/sh
set -e

# Larpnet.xcodeproj is generated from project.yml and is gitignored (see
# .gitignore), so Xcode Cloud's checkout doesn't have it. Regenerate it here
# before the archive/build/test action runs.
brew install xcodegen

cd "$CI_PRIMARY_REPOSITORY_PATH"
xcodegen generate

# Xcode Cloud's build environment disables automatic package resolution --
# even `xcodebuild -resolvePackageDependencies` run from here fails with
# "a resolved file is required when automatic dependency resolution is
# disabled". So instead of resolving, copy in the pinned Package.resolved
# committed at the repo root. Regenerate that file locally after changing
# dependencies with:
#   xcodebuild -resolvePackageDependencies -project Larpnet.xcodeproj -scheme Larpnet
#   cp Larpnet.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved Package.resolved
mkdir -p Larpnet.xcodeproj/project.xcworkspace/xcshareddata/swiftpm
cp Package.resolved Larpnet.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved

# Larpnet iOS

## Versioning

`MARKETING_VERSION`/`CURRENT_PROJECT_VERSION` in `project.yml` (lines ~72-73) must stay in sync
with the App Store release. When starting work on a new feature/release after a version has
shipped, bump `MARKETING_VERSION` to the next minor version past what's live on the App Store
(e.g. App Store is on 1.0 -> next branch is 1.1) and increment `CURRENT_PROJECT_VERSION` (the
build number) by 1. Run `xcodegen generate` afterward to regenerate the gitignored
`Larpnet.xcodeproj` with the new values.

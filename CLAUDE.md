# Larpnet iOS

## Versioning

`MARKETING_VERSION`/`CURRENT_PROJECT_VERSION` in `project.yml` (lines ~72-73) must stay in sync
with the App Store release. When starting work on a new feature/release after a version has
shipped, bump `MARKETING_VERSION` to the next minor version past what's live on the App Store
(e.g. App Store is on 1.0 -> next branch is 1.1) and increment `CURRENT_PROJECT_VERSION` (the
build number) by 1. Run `xcodegen generate` afterward to regenerate the gitignored
`Larpnet.xcodeproj` with the new values.

## Test account credentials

`.larpnet_testuser` at the repo root (gitignored, never commit it) holds login credentials for a
seeded test account, useful for manually exercising features that need a real logged-in session
(e.g. avatar upload, photo albums, moderation flows) without using the user's own account.
Two lines, no trailing newline: line 1 is the username, line 2 is the password.

`LarpnetUITests/TestServerSeedUITests.swift` is also gitignored -- it's a throwaway seed script
with 5 test accounts' passwords hardcoded in plaintext directly in the Swift source (confirmed
never committed to history; keep it that way). If a UI test genuinely needs credentials, follow
`ScreenshotVariantsUITests.swift`/`LoginFlowUITests.swift`'s pattern instead: read them from
`LARPNET_TEST_USERNAME`/`LARPNET_TEST_PASSWORD` environment variables, never hardcode them.

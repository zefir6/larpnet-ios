# Larpnet iOS

## Versioning

`MARKETING_VERSION`/`CURRENT_PROJECT_VERSION` in `project.yml` -- set in **both** targets (the app
and `LarpnetNotificationServiceExtension`; they must match) -- follow **one** version line that only
ever goes up, shared by internal TestFlight builds and App Store releases:

- Every push/merge to `test` (Xcode Cloud's internal-testing track): bump the minor component of
  `MARKETING_VERSION` (e.g. 1.34 -> 1.35), so every internal build carries its own distinct
  version. Also bump `CURRENT_PROJECT_VERSION` by 1 to keep local builds distinct, but note that
  **Xcode Cloud assigns the build number itself** (its own running counter -- e.g. builds 42/43
  for version 1.34), so the build number App Store Connect/TestFlight shows never comes from
  `project.yml`; only the version does. Run `xcodegen generate` afterward to regenerate the
  gitignored `Larpnet.xcodeproj` with the new values.
- An App Store release off `main` ships **whatever version `test` is already at** -- never
  renumber for a release, and never compute "next minor past what's live on the App Store".

Never decrease either number, and never reuse a version number that was already uploaded. This
rule exists because of 2026-10-14: a release was renumbered to "next past the live App Store
version" (1.5 -> 1.6 (8)) while `test` was already at 1.33 (35), and that number then got synced
back to `test`, so the line went backwards and reused old numbers. It was fixed by jumping both
branches to 1.34 (36).

**Server-side chat version gate:** friendica-larpnet's `larpnet_matrix_outdated_app_min_version()`
rejects chat login from iOS builds in the range [1.8, 1.31) -- old builds from before standard
encryption mode. Never number a build inside 1.8-1.30 again, or chat will refuse to log it in.

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

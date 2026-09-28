#!/bin/sh

# Posts the xcodebuild result as a GitHub commit status, so a build running
# in Xcode Cloud (which has no native GitHub integration/webhook of its
# own) shows up as a check on the commit/PR the same way any other CI
# would -- lets anyone (including an agent working via `gh`) see the build
# result without needing App Store Connect access.
#
# Deliberately its own script, separate from ci_post_clone.sh's project-setup
# work: that script uses `set -e` because a failure there must stop the
# build (a missing xcodegen/Package.resolved makes the build itself
# meaningless) -- this script must NEVER do that. Reporting a status is a
# pure side effect; every failure path below is caught and logged, and the
# script always exits 0, so a GitHub API hiccup (or a not-yet-configured
# token) can never turn a real, successful build into a reported failure.
#
# Runs once per xcodebuild action Xcode Cloud performs (build, archive, ...)
# -- CI_XCODEBUILD_ACTION is folded into the status `context` so e.g. a
# `build` action and a later `archive` action in the same workflow show up
# as two distinct checks rather than one overwriting the other.
#
# Requires a GitHub personal access token with "Commit statuses: write"
# (fine-grained, scoped to this repo) or the classic `repo:status` scope,
# stored as a SECRET environment variable named GITHUB_STATUS_TOKEN in this
# workflow's Environment settings in App Store Connect (Xcode Cloud ->
# workflow -> Environment -> Add Variable -> mark "Secret"). Never commit a
# real token here.

if [ "${CI_XCODE_CLOUD:-}" != "TRUE" ]; then
  exit 0
fi

if [ -z "${GITHUB_STATUS_TOKEN:-}" ]; then
  echo "ci_post_xcodebuild: GITHUB_STATUS_TOKEN not set, skipping GitHub status update"
  exit 0
fi

REMOTE_URL=$(git -C "$CI_PRIMARY_REPOSITORY_PATH" config --get remote.origin.url 2>/dev/null)
REPO=$(echo "$REMOTE_URL" | sed -E 's#^git@github\.com:##; s#^https://github\.com/##; s#\.git$##')

if [ -z "$REPO" ]; then
  echo "ci_post_xcodebuild: could not determine owner/repo from remote URL '$REMOTE_URL', skipping"
  exit 0
fi

if [ "${CI_XCODEBUILD_EXIT_CODE:-1}" = "0" ]; then
  STATE="success"
  DESCRIPTION="Xcode Cloud ${CI_XCODEBUILD_ACTION:-build} succeeded"
else
  STATE="failure"
  DESCRIPTION="Xcode Cloud ${CI_XCODEBUILD_ACTION:-build} failed (exit ${CI_XCODEBUILD_EXIT_CODE:-?})"
fi

curl -sS -o /dev/null -X POST \
  -H "Authorization: token ${GITHUB_STATUS_TOKEN}" \
  -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/${REPO}/statuses/${CI_COMMIT}" \
  -d "{
    \"state\": \"${STATE}\",
    \"target_url\": \"${CI_BUILD_URL:-}\",
    \"description\": \"${DESCRIPTION}\",
    \"context\": \"xcode-cloud/${CI_WORKFLOW:-build}/${CI_XCODEBUILD_ACTION:-build}\"
  }" \
  || echo "ci_post_xcodebuild: failed to post ${STATE} status to GitHub (non-fatal)"

exit 0

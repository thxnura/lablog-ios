#!/bin/zsh
# Runs the unit and UI tests against the HOSTED backend (Vercel + Supabase),
# with no local Docker stack (ADR-030).
#
#   scripts/test-hosted.sh                      every test
#   scripts/test-hosted.sh -only-testing:LabLogUITests/LabLogFlowUITests/testPendulumTimer
#
# Needs Config/Secrets.hosted.xcconfig (the app's hosted settings) and
# ../lablog-backend/.env.hosted (test-only accounts and the service-role key for
# the clean-up), both git-ignored. Before and after the run, everything the test
# accounts created is deleted, so the demo accounts and course labs never change.
# Extra arguments go to xcodebuild. Set DESTINATION or RESULT_BUNDLE to override.
set -euo pipefail
cd "${0:A:h}/.."
backend=../lablog-backend
[[ -f Config/Secrets.hosted.xcconfig ]] || { print -u2 "Missing Config/Secrets.hosted.xcconfig"; exit 1; }
[[ -f $backend/.env.hosted ]] || { print -u2 "Missing $backend/.env.hosted"; exit 1; }

(cd $backend && npm run -s hosted:users && npm run -s hosted:cleanup)

set -a; source $backend/.env.hosted; set +a
export TEST_RUNNER_LABLOG_TEST_HOSTED=1
for key in LABLOG_TEST_STUDENT LABLOG_TEST_STUDENT2 LABLOG_TEST_LECTURER; do
  export "TEST_RUNNER_$key=${(P)key}" "TEST_RUNNER_${key}_PASSWORD=${(P)${:-${key}_PASSWORD}}"
done

args=(-project LabLog.xcodeproj -scheme LabLog
      -destination "${DESTINATION:-platform=iOS Simulator,name=iPhone 17 Pro}")
[[ -n ${RESULT_BUNDLE:-} ]] && args+=(-resultBundlePath "$RESULT_BUNDLE")
result=0
xcodebuild test "${args[@]}" "$@" || result=$?

(cd $backend && npm run -s hosted:cleanup)
exit $result

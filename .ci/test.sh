#!/usr/bin/env bash

CI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${CI_DIR}/common.sh"

if [[ -z "${CIRCLE_PULL_REQUEST}" ]] && [[ "${CIRCLE_BRANCH}" == 'master' ]]; then
    # We're on master: do a full testsuite run with coverage.
    target='coverage'
else
    # Pull request / not on master: do a regular testsuite run.
    target='testfront'
fi

make "${target}" --assume-old=all T="-o '${PWD}/test-results.xml'"

# vim: sw=4

#!/usr/bin/env bash

CI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${CI_DIR}/common.sh"

set +e

if [ -z "${CIRCLE_PULL_REQUEST}" ] && [ "${CIRCLE_BRANCH}" = 'master' ]; then
    echo "CIRCLE_NODE_INDEX: ${CIRCLE_NODE_INDEX}"
    if [ "${CIRCLE_NODE_INDEX}" = 1 ]; then
        echo -e "\\n${ANSI_GREEN}Running make testfront for timings."
        make --assume-old=all testfront BUSTED_OVERRIDES="--output=junit -Xoutput junit-test-results.xml"
    fi

    if [ "${CIRCLE_NODE_INDEX}" = 0 ]; then
        travis_retry make --assume-old=all coverage
        pushd install/koreader && {
            # see https://github.com/codecov/example-lua
            bash <(curl -s https://codecov.io/bash)
        } && popd || exit
    fi
else
    echo -e "\\n${ANSI_GREEN}Not on official master branch. Skipping coverage."
fi

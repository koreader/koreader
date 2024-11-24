#!/usr/bin/env bash

CI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${CI_DIR}/common.sh"

set +e

if [ -z "${CIRCLE_PULL_REQUEST}" ] && [ "${CIRCLE_BRANCH}" = 'master' ]; then
    travis_retry make --assume-old=all coverage
    pushd install/koreader && {
        # see https://github.com/codecov/example-lua
        bash <(curl -s https://codecov.io/bash)
    } && popd || exit
else
    echo -e "\\n${ANSI_GREEN}Not on official master branch. Skipping coverage."
fi

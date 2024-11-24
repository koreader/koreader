#!/usr/bin/env bash

CI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${CI_DIR}/common.sh"

set +e

if [ -z "${CIRCLE_PULL_REQUEST}" ] && [ "${CIRCLE_BRANCH}" = 'master' ]; then
    echo -e "\\n${ANSI_GREEN}Uploading coverage."
    cd install/koreader && {
        # see https://github.com/codecov/example-lua
        bash <(curl -s https://codecov.io/bash)
    }
fi

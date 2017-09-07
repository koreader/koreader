#!/usr/bin/env bash

CI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${CI_DIR}/common.sh"

echo -e "\n${ANSI_GREEN}make fetchthirdparty"
bash "${CI_DIR}/fetch.sh"

echo -e "\n${ANSI_GREEN}static checks"
bash "${CI_DIR}/check.sh"

echo -e "\n${ANSI_GREEN}make all"
bash "${CI_DIR}/build.sh"

echo -e "\n${ANSI_GREEN}make testfront"
bash "${CI_DIR}/test.sh"

#!/usr/bin/env bash

CI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${CI_DIR}/common.sh"

make testfront --assume-old=all T="-o '${PWD}/test-results.xml'"

# vim: sw=4

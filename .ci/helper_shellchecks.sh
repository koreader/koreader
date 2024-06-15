#!/usr/bin/env bash

CI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${CI_DIR}/common.sh"

# shellcheck disable=2016
mapfile -t shellscript_locations < <({ git grep -lE '^#!(/usr)?/bin/(env )?(bash|sh)' | sed "/^plugins\/terminal.koplugin\/shfm$/d" && git submodule --quiet foreach '[ "$path" = "base" -o "$path" = "platform/android/luajit-launcher" ] || git grep -lE "^#!(/usr)?/bin/(env )?(bash|sh)" | sed "s|^|$path/|"' && git ls-files './*.sh'; } | sort | uniq)

./base/utils/shellcheck.sh "${shellscript_locations[@]}"

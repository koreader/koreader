#!/usr/bin/env bash

CI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${CI_DIR}/common.sh"

# shellcheck disable=2016
mapfile -t shellscript_locations < <({ git grep -lE '^#!(/usr)?/bin/(env )?(bash|sh)' && git submodule --quiet foreach '[ "$path" = "base" ] || git grep -lE "^#!(/usr)?/bin/(env )?(bash|sh)" | sed "s|^|$path/|"' && git ls-files ./*.sh; } | sort | uniq)

SHELLSCRIPT_ERROR=0

for shellscript in "${shellscript_locations[@]}"; do
    echo -e "${ANSI_GREEN}Running shellcheck on ${shellscript}"
    shellcheck "${shellscript}" || SHELLSCRIPT_ERROR=1
    echo -e "${ANSI_GREEN}Running shfmt on ${shellscript}"
    if [ "$(cat "${shellscript}")" != "$(shfmt -i 4 "${shellscript}")" ]; then
        echo -e "${ANSI_RED}Warning: ${shellscript} does not abide by coding style"
        shfmt -i 4 "${shellscript}" | diff "${shellscript}" - || SHELLSCRIPT_ERROR=1
    fi
done

exit "${SHELLSCRIPT_ERROR}"

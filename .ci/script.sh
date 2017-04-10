#!/usr/bin/env bash

CI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${CI_DIR}/common.sh"

echo -e "\n${ANSI_GREEN}make fetchthirdparty"
travis_retry make fetchthirdparty

# shellcheck disable=2016
mapfile -t shellscript_locations < <( { git grep -lE '^#!(/usr)?/bin/(env )?(bash|sh)' && git submodule --quiet foreach '[ "$path" = "base" ] || git grep -lE "^#!(/usr)?/bin/(env )?(bash|sh)" | sed "s|^|$path/|"' && git ls-files ./*.sh ; } | sort | uniq )

for shellscript in "${shellscript_locations[@]}"; do
    echo -e "\n${ANSI_GREEN}Running shellcheck on ${shellscript}"
    shellcheck "${shellscript}"
    echo -e "\n${ANSI_GREEN}Running shfmt on ${shellscript}"
    [ "$(cat "${shellscript}" )" != "$(shfmt -i 4 "${shellscript}")" ] && shfmt -i 4 "${shellscript}" | diff "${shellscript}" - > /dev/null 2>&1
    [ $? -eq 1 ] && echo  -e "\n${ANSI_GREEN}${shellscript} does not abide by coding style"
    # @TODO add "&& exit" when ready to change scripts
done

echo -e "\n${ANSI_GREEN}Luacheck results"
luajit "$(which luacheck)" --no-color -q {reader,setupkoenv,datastorage}.lua frontend plugins

echo -e "\n${ANSI_GREEN}make all"
make all
echo -e "\n${ANSI_GREEN}make testfront"
make testfront

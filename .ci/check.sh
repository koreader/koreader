#!/usr/bin/env bash

CI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${CI_DIR}/common.sh"

echo -e "\n${ANSI_GREEN}shellcheck results"
"${CI_DIR}/helper_shellchecks.sh"

echo -e "\\n${ANSI_GREEN}Checking for unscaled sizes"
# stick `|| true` at the end to prevent Travis exit on failed command
unscaled_size_check=$(grep -nr --include=*.lua --exclude=koptoptions.lua --exclude-dir=base --exclude-dir=luajit-rocks --exclude-dir=install --exclude-dir=keyboardlayouts --exclude-dir=*arm* "\\(padding\\|margin\\|bordersize\\|width\\|height\\|radius\\|linesize\\) = [0-9]\\{1,2\\}" | grep -v '= 0' | grep -v '= [0-9]/[0-9]' | grep -Ev '(default_option_height|default_option_padding)' | grep -v scaleBySize | grep -v 'unscaled_size_check: ignore' || true)
# Also check Geom objects; for legibility two regular expressions rather than
# one enormous indecipharable blob.
unscaled_size_check_geom=$(grep -E -nr --include=*.lua --exclude=gesturerange_spec.lua --exclude-dir=base --exclude-dir=luajit-rocks --exclude-dir=*arm* 'Geom:new{.+ [wh] = [0-9]{1,4}' | grep -Ev '[wh] = 0' | grep -v '= [0-9]/[0-9]' | grep -v scaleBySize || true)

if [ "${unscaled_size_check}" ] || [ "${unscaled_size_check_geom}" ]; then
    echo -e "\\n${ANSI_RED}Warning: it looks like you might be using unscaled sizes.\\nIt is almost always preferable to defer to one of the predefined sizes in ui.size in the following files:"
    echo "${unscaled_size_check}"
    echo "${unscaled_size_check_geom}"
    exit 1
fi

tab_detected=$(grep -P "\\t" --include \*.lua --exclude={dateparser.lua,xml.lua} --recursive {reader,setupkoenv,datastorage}.lua frontend plugins spec || true)
if [ "${tab_detected}" ]; then
    echo -e "\\n${ANSI_RED}Warning: tab character detected. Please use spaces."
    echo "${tab_detected}"
    exit 1
fi

untagged_todo=$(grep -Pin "[^\-]\-\-(\s+)?@?(todo|fixme|warning)" --include \*.lua --exclude={dateparser.lua,xml.lua} --recursive {reader,setupkoenv,datastorage}.lua frontend plugins spec || true)
if [ "${untagged_todo}" ]; then
    echo -e "\\n${ANSI_RED}Warning: possible improperly tagged todo, fixme or warning detected."
    echo -e "\\n${ANSI_RED}         use --- followed by @todo, @fixme or @warning."
    echo "${untagged_todo}"
    exit 1
fi

echo -e "\n${ANSI_GREEN}Luacheck results"
luajit "$(command -v luacheck)" --no-color -q {reader,setupkoenv,datastorage}.lua frontend plugins spec

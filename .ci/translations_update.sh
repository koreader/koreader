#!/usr/bin/env bash

CI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${CI_DIR}/common.sh"

[[ $# -eq 0 ]] || die "no expected, got $#"

template='templates/koreader.pot'
run make -f make/gettext.mk --assume-old=po pot
update_date="$(git log -1 --date='format:%Y-%m-%d %R%z' --format=format:%ad)"
run sed -i -e "s/^\"POT-Creation-Date: .*\\n\"$/\"POT-Creation-Date: ${update_date}\\n/" "l10n/${template}"
if run git -C l10n diff --exit-code --ignore-matching-lines='^"POT-Creation-Date: .*\\n"$' --patch-with-stat "${template}"; then
    echo -e "${ANSI_GREEN}No updated translations found."
    exit
fi
run git -C l10n -c user.name='KOReader build bot' -c user.email='non-reply@koreader.rocks' commit -m 'Updated translation source file' "${template}"
run git -C l10n push --quiet
echo -e "\\n${ANSI_GREEN}Translation update pushed."

#!/usr/bin/env bash

CI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${CI_DIR}/common.sh"

[[ $# -eq 0 ]] || die "no expected, got $#"

update_date="$(git log -1 --date=iso8601 --format=format:%ad)"
run env -C doc ldoc --date "${update_date}" .
run git -C doc/html add -A
if run git -C doc/html diff --exit-code --ignore-matching-lines='^<i[^>]*>Last updated [^<]*</i>$' --staged --patch-with-stat; then
    echo -e "${ANSI_GREEN}Documentation unchanged."
    exit
fi
run git -C doc/html -c user.name='KOReader build bot' -c user.email='non-reply@koreader.rocks' commit --amend -m 'Automated documentation build from CI.'
run git -C doc/html push -f --quiet
echo -e "\\n${ANSI_GREEN}Documentation update pushed."

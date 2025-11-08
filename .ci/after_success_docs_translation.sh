#!/usr/bin/env bash

CI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${CI_DIR}/common.sh"

set +e

echo -e "\\n${ANSI_GREEN}Updating translation source file."
pushd l10n && git fetch origin && git checkout master && popd || exit 1
make pot
pushd l10n && {
    # If only one line was added and removed, it was just the timestamp.
    git diff --numstat | grep "1[[:space:]]1[[:space:]]templates/koreader.pot" && echo -e "\\n${ANSI_GREEN}No updated translations found." || {
        git -c user.name="KOReader build bot" -c user.email="non-reply@koreader.rocks" \
            commit templates/koreader.pot -m "Updated translation source file"
        git push --quiet "https://${TRANSLATIONS_GITHUB_TOKEN}@github.com/koreader/koreader-translations.git" master
        echo -e "\\n${ANSI_GREEN}Translation update pushed."
    }
} && popd || exit 1

echo -e "\\n${ANSI_GREEN}Checking out koreader/doc for update."
git clone git@github.com:koreader/doc.git koreader_doc

# push doc update
pushd doc && {
    ldoc .
    if [ ! -d html ]; then
        echo "Failed to generate documents..."
        exit 1
    fi
} && popd || exit 1

cp -r doc/html/* koreader_doc/
pushd koreader_doc && {
    git add -A
    echo -e "\\n${ANSI_GREEN}Pushing document update..."
    git -c user.name="KOReader build bot" -c user.email="non-reply@koreader.rocks" \
        commit -a --amend -m 'Automated documentation build from travis-ci.'
    git push -f --quiet "https://${DOCS_GITHUB_TOKEN}@github.com/koreader/doc.git" gh-pages >/dev/null
    echo -e "\\n${ANSI_GREEN}Documentation update pushed."
} && popd || exit 1

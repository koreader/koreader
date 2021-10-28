#!/usr/bin/env bash

CI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${CI_DIR}/common.sh"

set +e

echo -e "\\n${ANSI_GREEN}Checking out koreader for doc update."
git clone git@github.com:koreader/doc.git koreader_doc

pushd doc && {
    ldoc .
    if [ ! -d html ]; then
        echo "Failed to generate documents..."
        exit 1
    fi
} && popd || exit

cp -r doc/html/* koreader_doc/.
pushd koreader_doc && {
    git diff
    git add -A
    echo -e "\\n${ANSI_GREEN}Pushing document update..."
    git -c user.name="KOReader build bot" -c user.email="non-reply@koreader.rocks" \
        commit -a --amend -m 'Automated documentation build from Github Actions.'
    git push -f -n "https://x-access-token${GITHUB_APP_TOKEN}@github.com/koreader/doc.git" gh-pages
    echo -e "\\n${ANSI_GREEN}Documentation update pushed."
} && popd || exit


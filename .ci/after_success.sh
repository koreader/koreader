#!/usr/bin/env bash

CI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${CI_DIR}/common.sh"

set +e

echo "CIRCLE_NODE_INDEX: ${CIRCLE_NODE_INDEX}"
if [ ! "$CIRCLE_NODE_INDEX" = 0 ]; then
    echo -e "\\n${ANSI_GREEN}Not on first node. Skipping documentation update and coverage."
elif [ -z "${CIRCLE_PULL_REQUEST}" ] && [ "${CIRCLE_BRANCH}" = 'master' ]; then
    echo -e "\\n${ANSI_GREEN}Checking out koreader/doc for update."
    git clone git@github.com:koreader/doc.git koreader_doc

    # push doc update
    pushd doc && {
        luajit "$(which ldoc)" . 2>/dev/null
        if [ ! -d html ]; then
            echo "Failed to generate documents..."
            exit 1
        fi
    } && popd || exit

    cp -r doc/html/* koreader_doc/
    pushd koreader_doc && {
        git add -A
        echo -e "\\n${ANSI_GREEN}Pushing document update..."
        git -c user.name="KOReader build bot" -c user.email="non-reply@koreader.rocks" \
            commit -a --amend -m 'Automated documentation build from travis-ci.'
        git push -f --quiet origin gh-pages >/dev/null
        echo -e "\\n${ANSI_GREEN}Documentation update pushed."
    } && popd || exit

    travis_retry make coverage
    pushd koreader-*/koreader && {
        # see https://github.com/codecov/example-lua
        bash <(curl -s https://codecov.io/bash)
    } && popd || exit
else
    echo -e "\\n${ANSI_GREEN}Not on official master branch. Skipping documentation update and coverage."
fi

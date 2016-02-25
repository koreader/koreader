#!/usr/bin/env bash

CI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${CI_DIR}/common.sh"

set +e

make coverage
pushd koreader-*/koreader
    luajit $(which luacov-coveralls) -v
popd

if [ ${TRAVIS_PULL_REQUEST} = false ] && [ ${TRAVIS_BRANCH} = 'master' ]; then
    travis_retry luarocks --local install ldoc
    # get deploy key for doc repo
    openssl aes-256-cbc -k $doc_build_secret -in .ci/koreader_doc.enc -out ~/.ssh/koreader_doc -d
    chmod 600 ~/.ssh/koreader_doc  # make agent happy
    eval "$(ssh-agent)" > /dev/null
    ssh-add ~/.ssh/koreader_doc > /dev/null
    echo -e "\n${ANSI_GREEN}Check out koreader/doc for update."
    git clone git@github.com:koreader/doc.git koreader_doc

    # push doc update
    pushd doc
        luajit $(which ldoc) . 2> /dev/null
        if [ ! -d html ]; then
            echo "Failed to generate documents..."
            exit 1
        fi
    popd
    cp -r doc/html/* koreader_doc/
    pushd koreader_doc

    echo -e "\n${ANSI_GREEN}Pusing document update..."
    git -c user.name="KOReader build bot" -c user.email="non-reply@koreader.rocks" \
        commit -a --amend -m 'Automated documentation build from travis-ci.'
    git push -f --quiet origin gh-pages > /dev/null
    echo -e "\n${ANSI_GREEN}Document update pushed."
else
    echo -e "\n${ANSI_GREEN}Not on official master branch, skip document update."
fi

#!/usr/bin/env bash

make coverage
cd koreader-*/koreader && luajit $(which luacov-coveralls) -v

# get deploy key for doc repo
openssl aes-256-cbc -K $encrypted_dc71a4fb8382_key -iv $encrypted_dc71a4fb8382_iv \
    -in .ci/koreader_doc.enc -out ~/.ssh/koreader_doc -d
ssh-add ~/.ssh/koreader_doc
git clone git@github.com:koreader/doc.git
# push doc update
make doc
cp -r doc/html/* doc/
pushd doc
git add .
git push origin gh-pages

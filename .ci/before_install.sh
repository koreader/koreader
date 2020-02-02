#!/usr/bin/env bash

# don't do this for clang
if [ "${CXX}" = "g++" ]; then
    export CXX="g++-5" CC="gcc-5"
fi
# in case anything ignores the environment variables, override through PATH
mkdir bin
ln -s "$(command -v gcc-5)" bin/cc
ln -s "$(command -v gcc-5)" bin/gcc
ln -s "$(command -v c++)" bin/c++
ln -s "$(command -v g++-5)" bin/g++

# Travis only makes a shallow clone of --depth=50. KOReader is small enough that
# we can just grab it all. This is necessary to generate the version number,
# without which some tests will fail.
# git fetch --unshallow

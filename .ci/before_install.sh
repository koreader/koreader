#!/usr/bin/env bash

# don't do this for clang
if [ "$CXX" = "g++" ]; then
    export CXX="g++-4.8" CC="gcc-4.8"
fi
# in case anything ignores the environment variables, override through PATH
mkdir bin
ln -s "$(which gcc-4.8)" bin/cc
ln -s "$(which gcc-4.8)" bin/gcc
ln -s "$(which c++-4.8)" bin/c++
ln -s "$(which g++-4.8)" bin/g++

# Travis only makes a shallow clone of --depth=50. KOReader is small enough that
# we can just grab it all. This is necessary to generate the version number,
# without which some tests will fail.
git fetch --unshallow

#!/bin/bash

# usage: bash document_events.sh [0|1] path1, path2, path3 ...

if [[ "$?" == "1" ]]; then
    echo "usage: bash documented_events.sh path1, path2, path3 ..."
    exit 1
fi

LUA_SCRIPT=${0//\.sh/\.lua}

find -L "$@" -maxdepth 50 -name "*.lua" -exec lua "${LUA_SCRIPT}" {} \;


#!/bin/bash

# usage: bash document_events.sh [0|1] path1, path2, path3 ...

if [[ "$1" == "0" ]]; then
    FILENAME=undocumentedEvents.txt
    rm -f ${FILENAME}
elif [[ "$1" == "1" ]]; then
    FILENAME=documentedEvents.txt
    rm -f ${FILENAME}
elif [[ "$1" == "2" ]]; then
    FILENAME="/dev/null"
else
    echo "usage: bash documented_events.sh [0|1|2] path1, path2, path3 ..."
    echo "    0 find undocumented; 1 find documented; 2 document undocumented"
    exit 1
fi

MODE=$1
LUA_SCRIPT=${0//\.sh/\.lua}

shift 1
find -L "$@" -maxdepth 50 -name "*.lua" -exec lua "${LUA_SCRIPT}" "${MODE}" {} \; >>${FILENAME}

if [[ "${FILENAME}" =~ "/dev/null" ]]; then
    echo results can be found in ${FILENAME}
fi


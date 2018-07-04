#!/bin/sh

# KOReader's working directory
KOREADER_DIR="/mnt/us/koreader"

# We do NOT want to sleep during eips calls!
export EIPS_NO_SLEEP="true"

# Load our helper functions...
if [ -f "${KOREADER_DIR}/libkohelper.sh" ]; then
    # shellcheck source=/dev/null
    . "${KOREADER_DIR}/libkohelper.sh"
else
    echo "Can't source helper functions, aborting!"
    exit 1
fi

# What are we printing?
case "${1}" in
    "clear")
        eips_print_bottom_centered " " 3
        eips_print_bottom_centered " " 2
        ;;
    *)
        eips_print_bottom_centered "Computing zsync delta . . ." 3
        ;;
esac

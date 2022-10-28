#!/bin/sh

# This script is safe to run multiple times

if ! [ -d /sys/kernel/debug ]; then
    echo "The kernel does not support debugfs. It must be built with CONFIG_DEBUG_FS set."
    exit 1
fi

if ! grep -q "^none /sys/kernel/debug debugfs" "/proc/mounts"; then
    if ! mount -t debugfs none /sys/kernel/debug; then
        echo "Failed to mount debugfs"
        exit 1
    fi
fi

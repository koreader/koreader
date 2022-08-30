#!/bin/sh

# This script is safe to run multiple times

if ! [ -d /sys/kernel/debug ]; then
    echo "The kernel does not support debugfs. It must be built with CONFIG_DEBUG_FS set."
    exit 1
fi

if [ -z "$(ls /sys/kernel/debug)" ]; then
    mount -t debugfs none /sys/kernel/debug/
    if [ $? ]; then
        echo "Failed to mount debugfs"
        exit 1
    fi
fi

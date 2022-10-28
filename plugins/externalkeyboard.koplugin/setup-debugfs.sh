#!/bin/sh

# This script is safe to run multiple times
if ! grep -q "^none /sys/kernel/debug debugfs" "/proc/mounts"; then
    if ! mount -t debugfs none /sys/kernel/debug; then
        echo "Failed to mount debugfs"
        exit 1
    fi
fi

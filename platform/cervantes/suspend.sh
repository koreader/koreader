#! /bin/sh

# De-activate the touch screen.
echo 1 >/sys/power/state-extended

# Prevent the following error on the last line:
# *write error: Operation not permitted*.
sleep 2

# Synchronize the file system.
sync

# Suspend to RAM.
echo mem >/sys/power/state

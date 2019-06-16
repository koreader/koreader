#!/bin/sh
# This script exits KOReader and loads the default BQ Reader App
# Copy it to /usr/bin so that it can be used by simply writing switch.sh on the terminal emulator plugin of KOReader
#
# It can also be invoked with the exit command on KOReader by modifying /etc/rc.local like this:
#
# REPLACE THIS CODE:
# check if KOReader script exists.
#  if [ -x /mnt/private/koreader/koreader.sh ]; then
#     # yada! KOReader is installed and ready to run.
#     while true; do
#         /mnt/private/koreader/koreader.sh
#         if [ -x /usr/bin/safemode ]; then
#             safemode storage || sleep 1
#         else
#             sleep 1
#         fi
#     done
#
#
# WITH THIS CODE:
# check if KOReader script exists.
#  if [ -x /mnt/private/koreader/koreader.sh ]; then
#     # yada! KOReader is installed and ready to run.
#     while true; do
#         /mnt/private/koreader/koreader.sh
#         /usr/bin/switch.sh
#     done

killall koreader.sh
killall reader.lua        # Exit KOReader so that the touchcreen can be used by BQ Reader App
/etc/init.d/connman start # Start connman in order to be able to use WiFi
/usr/bin/restart.sh       # Launch BQ Reader App

# General

When connected to Wi-Fi you can find the IP address and root password for your
reMarkable in Settings -> About, then scroll down the GPLv3 compliance on the
right (finger drag scroll, not the page forward/back buttons). This should also
work for the USB network you get if you connect the reMarkable to your computer
with a USB cable.

# Install

   scp <koreader-package>.zip root@<your-remarkable>:

   ssh root@<your-remarkable>

   unzip <koreader-package>.zip

# Launching using the included launcher

KOReader includes a very simple launcher called `button-listen` which starts
KOReader when the middle button is held down for 3 or more seconds in the
default UI (xochitl).

   cp -v koreader/*.service /etc/systemd/system/
   systemctl enable --now button-listen

To return to the default UI just exit KOReader (swipe down from the top of the
screen, select icon in the top right, Exit, Exit).

Some reMarkable software updates will wipe the new systemd units so you will have
to run the two install steps again when that happens.

# Using a different launcher

The command that the launcher needs to run is:

   /home/root/koreader/koreader.sh

Alternatively, if you want the default behaviour of KOReader exit starting the
default UI you can run (once on installation):

   cp -v koreader/koreader.service /etc/systemd/system/

Then to start KOReader the launcher needs to run:

   systemctl start koreader

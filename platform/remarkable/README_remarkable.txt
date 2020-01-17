# Install

   scp <koreader-package>.zip <your-remarkable>:

   ssh <your-remarkable>

   unzip <koreader-package>.zip
   cp -v koreader/*.service /etc/systemd/system/
   systemctl enable button-listen
   systemctl start button-listen

Hold down the middle button for 3 seconds to start koreader. To return to
xochitl just exit koreader (swipe down from the top of the screen, select icon
in the top right, Exit, Exit).

#!/bin/sh
export LC_ALL="en_US.UTF-8"

# we're always starting from our working directory
cd /mnt/onboard/.kobo/koreader/

# export trained OCR data directory
export TESSDATA_PREFIX="data"

# export dict directory
export STARDICT_DATA_DIR="data/dict"

# stop Nickel
killall -STOP nickel

# store the content of the framebuffer
#dd if=/dev/fb0 of=.last_screen_content

# finally call reader
./reader.lua /mnt/onboard 2> crash.log

# continue with nickel
killall -CONT nickel

# return to home screen
cd /mnt/onboard/.kobo/koreader/Kobo2HomeScreen
case `/bin/kobo_config.sh * 2>/dev/null` in
	dragon)		#DEVICE=AURAHD 
				#no binary file available
		;;
	phoenix)	#DEVICE=AURA
				cat ./KoboAuraTapHomeIcon.bin > /dev/input/event1
				cat ./KoboAuraTapHomeIcon.bin > /dev/input/event1
		;;
	kraken)		#DEVICE=GLO    
				#no binary file available
		;;
	pixie)		#DEVICE=MINI   
				cat ./KoboMiniTapHomeIcon.bin > /dev/input/event1
				cat ./KoboMiniTapHomeIcon.bin > /dev/input/event1
		;;
	trilogy|*)	#DEVICE=TOUCH
				cat ./KoboTouchHomeButton.bin > /dev/input/event0
		;;
esac
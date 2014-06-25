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

# chandravadan's fix START
#Before calling the reader, run a script in background that would prevent the device from sleep crashing
sh ./crashfix.sh &

#record pid of the process that runs, so it can be killed later
echo $!> waiter.pid
# chandravadan's fix END


./reader.lua /mnt/onboard 2> crash.log
#./reader.lua -d /mnt/onboard > ./koreader_debug.log 2>&1

# continue with nickel

# chandravadan's fix START
#kill the waiter process
kill `cat waiter.pid`
echo "killed waiter" >>test.log
# chandravadan's fix END


killall -CONT nickel

# return to home screen
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
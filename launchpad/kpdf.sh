echo unlock > /proc/keypad
echo unlock > /proc/fiveway
cd /mnt/us/test/
cat /dev/fb0 > screen.fb0 &
pdf=`lsof | grep /mnt/us/documents | cut -c81- | sort -u`
./reader.lua "$pdf"
cat screen.fb0 > /dev/fb0
echo 1 > /proc/eink_fb/update_display

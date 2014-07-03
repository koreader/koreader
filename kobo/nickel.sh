#!/bin/sh
PATH=$PATH:/usr/sbin:/sbin

# start fmon again:
( usleep 400000; /etc/init.d/on-animator.sh ) &

# environment needed by nickel, from /etc/init.d/rcS:
PLATFORM=freescale                                                              
if [ `dd if=/dev/mmcblk0 bs=512 skip=1024 count=1 | grep -c "HW CONFIG"` == 1 ]; then
  CPU=`ntx_hwconfig -s -p /dev/mmcblk0 CPU 2>/dev/null`
  PLATFORM=$CPU-ntx                
fi                                 
                                                               
if [ $PLATFORM != freescale ]; then                            
  INTERFACE=eth0                                               
  WIFI_MODULE=dhd                                              
else                                                                            
  INTERFACE=wlan0                                                               
  WIFI_MODULE=ar6000                                                            
fi                                                                              
                                                                                
export PLATFORM                                                                 
export INTERFACE                                                                
export WIFI_MODULE                                                              
export WIFI_MODULE_PATH=/drivers/$PLATFORM/wifi/$WIFI_MODULE.ko
export NICKEL_HOME=/mnt/onboard/.kobo                                           
export LD_LIBRARY_PATH=/usr/local/Kobo

# start nickel again (from tshering's start menu v0.4), this should
# cover all firmware versions from 2.6.1 to 3.4.1 (tested on a kobo
# mini with 3.4.1 firmware)

( /usr/local/Kobo/pickel disable.rtc.alarm                                      
  if [ ! -e /etc/wpa_supplicant/wpa_supplicant.conf ]; then                     
    cp /etc/wpa_supplicant/wpa_supplicant.conf.template /etc/wpa_supplicant/wpa_supplicant.conf
  fi                                                                            
  echo 1 > /sys/devices/platform/mxc_dvfs_core.0/enable                         
  /sbin/hwclock -s -u                                                           
) & 

if [ ! -e /usr/local/Kobo/platforms/libkobo.so ]; then                          
    export QWS_KEYBOARD=imx508kbd:/dev/input/event0                             
    export QT_PLUGIN_PATH=/usr/local/Kobo/plugins                               
    if [ -e /usr/local/Kobo/plugins/gfxdrivers/libimxepd.so ]; then             
        export QWS_DISPLAY=imxepd                                               
    else                                                                        
        export QWS_DISPLAY=Transformed:imx508:Rot90                             
        export QWS_MOUSE_PROTO="tslib_nocal:/dev/input/event1"                  
    fi                                                                          
    /usr/local/Kobo/hindenburg &                                                
    /usr/local/Kobo/nickel -qws -skipFontLoad                                   
else
    /usr/local/Kobo/hindenburg &
    insmod /drivers/$PLATFORM/misc/lowmem.ko &
    [ `cat /mnt/onboard/.kobo/Kobo/Kobo\ eReader.conf | grep -c dhcpcd=true` == 1 ] && dhcpcd -d -t 10 &
    /usr/local/Kobo/nickel -platform kobo -skipFontLoad
fi

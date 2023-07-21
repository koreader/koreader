#!/bin/sh

# Disable wifi, and remove all modules.
# NOTE: Save our resolv.conf to avoid ending up with an empty one, in case the DHCP client wipes it on release (#6424).
cp -a "/etc/resolv.conf" "/tmp/resolv.ko"
old_hash="$(md5sum "/etc/resolv.conf" | cut -f1 -d' ')"

if [ -x "/sbin/dhcpcd" ]; then
    dhcpcd -d -k "${INTERFACE}"
    killall -q -TERM udhcpc default.script
else
    killall -q -TERM udhcpc default.script dhcpcd
fi

# NOTE: dhcpcd -k waits for the signalled process to die, but busybox's killall doesn't have a -w, --wait flag,
#       so we have to wait for udhcpc to die ourselves...
# NOTE: But if all is well, there *isn't* any udhcpc process or script left to begin with...
kill_timeout=0
while pkill -0 udhcpc; do
    # Stop waiting after 5s
    if [ ${kill_timeout} -ge 20 ]; then
        break
    fi
    usleep 250000
    kill_timeout=$((kill_timeout + 1))
done

new_hash="$(md5sum "/etc/resolv.conf" | cut -f1 -d' ')"
# Restore our network-specific resolv.conf if the DHCP client wiped it when releasing the lease...
if [ "${new_hash}" != "${old_hash}" ]; then
    mv -f "/tmp/resolv.ko" "/etc/resolv.conf"
else
    rm -f "/tmp/resolv.ko"
fi

wpa_cli -i "${INTERFACE}" terminate

[ "${WIFI_MODULE}" = "dhd" ] && wlarm_le -i "${INTERFACE}" down
ifconfig "${INTERFACE}" down

# Handle dependencies, if any
WIFI_DEP_MOD=""
# Honor the platform's preferred method to toggle power
POWER_TOGGLE="module"
# Some platforms never unload the wifi modules
SKIP_UNLOAD=""
case "${WIFI_MODULE}" in
    "moal")
        WIFI_DEP_MOD="mlan"
        POWER_TOGGLE="ntx_io"
        ;;
    "wlan_drv_gen4m")
        POWER_TOGGLE="wmt"
        SKIP_UNLOAD="true"
        ;;
esac

if [ -z "${SKIP_UNLOAD}" ]; then
    # Some sleep in between may avoid system getting hung
    # (we test if a module is actually loaded to avoid unneeded sleeps)
    if grep -q "^${WIFI_MODULE} " "/proc/modules"; then
        usleep 250000
        # NOTE: Kobo's busybox build is weird. rmmod appears to be modprobe in disguise, defaulting to the -r flag...
        #       But since there's currently no modules.dep file being shipped, nor do they include the depmod applet,
        #       go with what the FW is doing, which is rmmod.
        # c.f., #2394?
        rmmod "${WIFI_MODULE}"
    fi

    if [ -n "${WIFI_DEP_MOD}" ]; then
        if grep -q "^${WIFI_DEP_MOD} " "/proc/modules"; then
            usleep 250000
            rmmod "${WIFI_DEP_MOD}"
        fi
    fi
fi

case "${POWER_TOGGLE}" in
    "ntx_io")
        usleep 250000
        ./luajit frontend/device/kobo/ntx_io.lua 208 0
        ;;
    "wmt")
        echo 0 >/dev/wmtWifi
        ;;
    *)
        if grep -q "^sdio_wifi_pwr " "/proc/modules"; then
            # Handle the shitty DVFS switcheroo...
            if [ -n "${CPUFREQ_DVFS}" ]; then
                echo "0" >"/sys/devices/platform/mxc_dvfs_core.0/enable"
                if [ -n "${CPUFREQ_CONSERVATIVE}" ]; then
                    echo "conservative" >"/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor"
                else
                    echo "userspace" >"/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor"
                    cat "/sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq" >"/sys/devices/system/cpu/cpu0/cpufreq/scaling_setspeed"
                fi
            fi
            usleep 250000
            rmmod sdio_wifi_pwr
        fi

        # Poke the kernel via ioctl on platforms without the dedicated power module...
        if [ ! -e "/drivers/${PLATFORM}/wifi/sdio_wifi_pwr.ko" ]; then
            usleep 250000
            ./luajit frontend/device/kobo/ntx_io.lua 208 0
        fi
        ;;
esac

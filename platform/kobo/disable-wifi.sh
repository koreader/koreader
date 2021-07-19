#!/bin/sh

# Disable wifi, and remove all modules.
# NOTE: Save our resolv.conf to avoid ending up with an empty one, in case the DHCP client wipes it on release (#6424).
cp -a "/etc/resolv.conf" "/tmp/resolv.ko"
old_hash="$(md5sum "/etc/resolv.conf" | cut -f1 -d' ')"

if [ -x "/sbin/dhcpcd" ]; then
    env -u LD_LIBRARY_PATH dhcpcd -d -k "${INTERFACE}"
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

wpa_cli terminate

[ "${WIFI_MODULE}" = "dhd" ] && wlarm_le -i "${INTERFACE}" down
ifconfig "${INTERFACE}" down

# Some sleep in between may avoid system getting hung
# (we test if a module is actually loaded to avoid unneeded sleeps)
if grep -q "${WIFI_MODULE}" "/proc/modules"; then
    usleep 250000
    rmmod "${WIFI_MODULE}"
fi
if grep -q "sdio_wifi_pwr" "/proc/modules"; then
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

#!/bin/sh

# NOTE: Close any non-standard fds, so that it doesn't come back to bite us in the ass with USBMS (or sockets) later...
for fd in /proc/"$$"/fd/*; do
    close_me="false"
    fd_id="$(basename "${fd}")"
    fd_path="$(readlink -f "${fd}")"

    if [ -e "${fd}" ] && [ "${fd_id}" -gt 2 ]; then
        if [ -S "${fd}" ]; then
            # Close any and all sockets
            # NOTE: Old busybox builds do something stupid when attempting to canonicalize pipes/sockets...
            #       (i.e., they'll spit out ${fd} as-is, losing any and all mention of a socket/pipe).
            fd_path="$(readlink "${fd}")"
            close_me="true"
        elif [ -p "${fd}" ]; then
            # We *might* be catching temporary pipes created by this very test, se we have to leave pipes alone...
            # Although it would take extremely unlucky timing, as by the time we go through the top-level -e test,
            # said temporary pipe is already gone, and as such we *should* never really enter this branch for temporary pipes ;).
            fd_path="$(readlink "${fd}")"
            close_me="false"
        else
            # NOTE: dash (meaning, in turn, busybox's ash) uses fd 10+ open to /dev/tty or $0 (w/ CLOEXEC)
            # NOTE: The last fd != fd_path check is there to (potentially) whitelist non-regular files we might have failed to handle,
            #       it's designed to match the unhelpful result from old buysbox's readlink -f on non-regular files (c.f., previous notes).
            if [ "${fd_path}" != "/dev/tty" ] && [ "${fd_path}" != "$(readlink -f "${0}")" ] && [ "${fd}" != "${fd_path}" ]; then
                close_me="true"
            else
                close_me="false"
            fi
        fi
    fi

    if [ "${fd_id}" -gt 2 ]; then
        if [ "${close_me}" = "true" ]; then
            eval "exec ${fd_id}>&-"
            echo "[enable-wifi.sh] Closed fd ${fd_id} -> ${fd_path}"
        else
            # Try to log something more helpful when old busybox's readlink -f mangled it...
            if [ "${fd}" = "${fd_path}" ]; then
                fd_path="${fd_path} => $(readlink "${fd}")"
                if [ ! -e "${fd}" ]; then
                    # Flag (potentially?) temporary items as such
                    fd_path="${fd_path} (temporary?)"
                fi
            fi
            echo "[enable-wifi.sh] Left fd ${fd_id} -> ${fd_path} open"
        fi
    fi
done

# Some platforms do *NOT* use sdio_wifi_pwr, even when it is physically there...
POWER_TOGGLE="module"
# We also want to choose the wpa_supplicant driver depending on the module...
WPA_SUPPLICANT_DRIVER="wext"
# And some platforms also put the modules in some funkier paths...
KMOD_PATH="/drivers/${PLATFORM}/wifi"
case "${WIFI_MODULE}" in
    "moal")
        POWER_TOGGLE="ntx_io"
        WPA_SUPPLICANT_DRIVER="nl80211"
        ;;
    "wlan_drv_gen4m")
        POWER_TOGGLE="wmt"
        WPA_SUPPLICANT_DRIVER="nl80211"
        KMOD_PATH="/drivers/${PLATFORM}/mt66xx"
        ;;
esac

# Load the requested module if it isn't already
insmod_asneeded() {
    kmod="${1}"
    shift

    if ! grep -q "^${kmod} " "/proc/modules"; then
        insmod "${KMOD_PATH}/${kmod}.ko" "${@}"
        usleep 250000
    fi
}

# Power up WiFi chip
case "${POWER_TOGGLE}" in
    "ntx_io")
        # 208 is CM_WIFI_CTRL
        ./luajit frontend/device/kobo/ntx_io.lua 208 1
        ;;
    "wmt")
        # NOTE: Unlike earlier platforms, it seems the WiFi modules are only loaded once, and never unloaded.
        #       So, just make sure they actually are loaded before we go on...
        insmod_asneeded "wmt_drv"
        insmod_asneeded "wmt_chrdev_wifi"
        insmod_asneeded "wmt_cdev_bt"
        insmod_asneeded "${WIFI_MODULE}"

        # Black magic courtesy of wmt_dbg_func_ctrl @ (out of tree) modules/connectivity/wmt_mt66xx/common_main/linux/wmt_dbg.c
        # Enable debug commands
        echo "0xDB9DB9" >/proc/driver/wmt_dbg
        # Disable the LPBK test
        echo "7 9 0" >/proc/driver/wmt_dbg
        # Nickel appears to sleep for ~1s
        sleep 1
        echo "0xDB9DB9" >/proc/driver/wmt_dbg
        # Enable the LPBK test (this'll block for ~1.3s)
        echo "7 9 1" >/proc/driver/wmt_dbg
        # Finally, power on the chip
        echo 1 >/dev/wmtWifi
        ;;
    *)
        if ! grep -q "^sdio_wifi_pwr " "/proc/modules"; then
            if [ -e "${KMOD_PATH}/sdio_wifi_pwr.ko" ]; then
                # Handle the shitty DVFS switcheroo...
                if [ -n "${CPUFREQ_DVFS}" ]; then
                    echo "userspace" >"/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor"
                    echo "1" >"/sys/devices/platform/mxc_dvfs_core.0/enable"
                fi

                insmod "${KMOD_PATH}/sdio_wifi_pwr.ko"
            else
                # Poke the kernel via ioctl on platforms without the dedicated power module...
                ./luajit frontend/device/kobo/ntx_io.lua 208 1
            fi
        fi
        ;;
esac
# Moar sleep!
usleep 250000

# Load WiFi modules
# NOTE: Used to be exported in WIFI_MODULE_PATH before FW 4.23
if ! grep -q "^${WIFI_MODULE} " "/proc/modules"; then
    # Set the Wi-Fi regulatory domain properly if necessary...
    WIFI_COUNTRY_CODE_PARM=""
    if grep -q "^WifiRegulatoryDomain=" "/mnt/onboard/.kobo/Kobo/Kobo eReader.conf"; then
        WIFI_COUNTRY_CODE="$(grep "^WifiRegulatoryDomain=" "/mnt/onboard/.kobo/Kobo/Kobo eReader.conf" | cut -d '=' -f2)"

        case "${WIFI_MODULE}" in
            "8821cs")
                WIFI_COUNTRY_CODE_PARM="rtw_country_code=${WIFI_COUNTRY_CODE}"
                ;;
            "moal")
                WIFI_COUNTRY_CODE_PARM="reg_alpha2=${WIFI_COUNTRY_CODE}"
                ;;
        esac
    fi

    VENDOR_WIFI_PARM=""
    case "${WIFI_MODULE}" in
        "moal")
            # NXP's driver for the Marvell 88W8987 RF SoC needs to be told what to choose between client, AP & WiFi DIRECT mode.
            VENDOR_WIFI_PARM="mod_para=nxp/wifi_mod_para_sd8987.conf"

            # And, of course, it requires a submodule...
            WIFI_DEP_MOD="mlan"
            insmod "${KMOD_PATH}/${WIFI_DEP_MOD}.ko"
            # NOTE: Nickel sleeps for two whole seconds after each module loading.
            #       Let's try our usual timing instead...
            usleep 250000
            ;;
        "wlan_drv_gen4m")
            # Nothing to do here, we only load the modules once, so we should never enter this branch.
            ;;
    esac

    WIFI_PARM=""
    if [ -n "${WIFI_COUNTRY_CODE_PARM}" ]; then
        if [ -n "${WIFI_PARM}" ]; then
            WIFI_PARM="${WIFI_PARM} ${WIFI_COUNTRY_CODE_PARM}"
        else
            WIFI_PARM="${WIFI_COUNTRY_CODE_PARM}"
        fi
    fi
    if [ -n "${VENDOR_WIFI_PARM}" ]; then
        if [ -n "${WIFI_PARM}" ]; then
            WIFI_PARM="${WIFI_PARM} ${VENDOR_WIFI_PARM}"
        else
            WIFI_PARM="${VENDOR_WIFI_PARM}"
        fi
    fi

    if [ -e "${KMOD_PATH}/${WIFI_MODULE}.ko" ]; then
        if [ -n "${WIFI_PARM}" ]; then
            # shellcheck disable=SC2086
            insmod "${KMOD_PATH}/${WIFI_MODULE}.ko" ${WIFI_PARM}
        else
            insmod "${KMOD_PATH}/${WIFI_MODULE}.ko"
        fi
    elif [ -e "/drivers/${PLATFORM}/${WIFI_MODULE}.ko" ]; then
        # NOTE: Modules are unsorted on Mk. 8
        if [ -n "${WIFI_PARM}" ]; then
            # shellcheck disable=SC2086
            insmod "/drivers/${PLATFORM}/${WIFI_MODULE}.ko" ${WIFI_PARM}
        else
            insmod "/drivers/${PLATFORM}/${WIFI_MODULE}.ko"
        fi
    fi
fi

# Race-y as hell, don't try to optimize this!
# NOTE: We're after a module insert, meaning Nickel may sleep for two whole seconds here.
case "${WIFI_MODULE}" in
    "moal")
        # NOTE: Bringup may be genuinely slower than usual with this chip, so, mimic Nickel's sleep patterns.
        sleep 2
        ;;
    *)
        sleep 1
        ;;
esac

# Bring the network interface up & setup WiFi
ifconfig "${INTERFACE}" up
[ "${WIFI_MODULE}" = "dhd" ] && wlarm_le -i "${INTERFACE}" up

pkill -0 wpa_supplicant ||
    wpa_supplicant -D "${WPA_SUPPLICANT_DRIVER}" -s -i "${INTERFACE}" -c /etc/wpa_supplicant/wpa_supplicant.conf -C /var/run/wpa_supplicant -B

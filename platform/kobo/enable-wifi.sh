#!/bin/sh

# NOTE: Close any non-standard fds, so that it doesn't come back to bite us in the ass with USBMS later...
for fd in /proc/"$$"/fd/*; do
    fd_id="$(basename "${fd}")"
    if [ -e "${fd}" ] && [ "${fd_id}" -gt 2 ]; then
        # NOTE: dash (meaning, in turn, busybox's ash, uses fd 10+ open to /dev/tty or $0 (w/ CLOEXEC))
        fd_path="$(readlink -f "${fd}")"
        if [ "${fd_path}" != "/dev/tty" ] && [ "${fd_path}" != "$(readlink -f "${0}")" ] && [ "${fd}" != "${fd_path}" ]; then
            eval "exec ${fd_id}>&-"
            echo "[enable-wifi.sh] Closed fd ${fd_id} -> ${fd_path}"
        fi
    fi
done

# Some platforms do *NOT* use sdio_wifi_pwr, even when it is physically there...
SKIP_SDIO_PWR_MODULE=""
# We also want to choose the wpa_supplicant driver depending on the module...
WPA_SUPPLICANT_DRIVER="wext"
case "${WIFI_MODULE}" in
    "moal")
        SKIP_SDIO_PWR_MODULE="1"
        WPA_SUPPLICANT_DRIVER="nl80211"
        ;;
esac

# Power up WiFi chip
if [ -n "${SKIP_SDIO_PWR_MODULE}" ]; then
    # 208 is CM_WIFI_CTRL
    ./luajit frontend/device/kobo/ntx_io.lua 208 1
else
    if ! grep -q "^sdio_wifi_pwr" "/proc/modules"; then
        if [ -e "/drivers/${PLATFORM}/wifi/sdio_wifi_pwr.ko" ]; then
            # Handle the shitty DVFS switcheroo...
            if [ -n "${CPUFREQ_DVFS}" ]; then
                echo "userspace" >"/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor"
                echo "1" >"/sys/devices/platform/mxc_dvfs_core.0/enable"
            fi

            insmod "/drivers/${PLATFORM}/wifi/sdio_wifi_pwr.ko"
        else
            # Poke the kernel via ioctl on platforms without the dedicated power module...
            # 208 is CM_WIFI_CTRL
            ./luajit frontend/device/kobo/ntx_io.lua 208 1
        fi
    fi
fi
# Moar sleep!
usleep 250000

# Load WiFi modules
# NOTE: Used to be exported in WIFI_MODULE_PATH before FW 4.23
if ! grep -q "^${WIFI_MODULE}" "/proc/modules"; then
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
            if [ -e "/drivers/${PLATFORM}/wifi/${WIFI_DEP_MOD}.ko" ]; then
                insmod "/drivers/${PLATFORM}/wifi/${WIFI_DEP_MOD}.ko"
            elif [ -e "/drivers/${PLATFORM}/${WIFI_DEP_MOD}.ko" ]; then
                insmod "/drivers/${PLATFORM}/${WIFI_DEP_MOD}.ko"
            fi
            # NOTE: Nickel sleeps for two whole seconds after each module loading.
            #       Let's try our usual timing instead...
            usleep 250000
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

    if [ -e "/drivers/${PLATFORM}/wifi/${WIFI_MODULE}.ko" ]; then
        if [ -n "${WIFI_PARM}" ]; then
            # shellcheck disable=SC2086
            insmod "/drivers/${PLATFORM}/wifi/${WIFI_MODULE}.ko" ${WIFI_PARM}
        else
            insmod "/drivers/${PLATFORM}/wifi/${WIFI_MODULE}.ko"
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
    env -u LD_LIBRARY_PATH \
        wpa_supplicant -D "${WPA_SUPPLICANT_DRIVER}" -s -i "${INTERFACE}" -c /etc/wpa_supplicant/wpa_supplicant.conf -C /var/run/wpa_supplicant -B

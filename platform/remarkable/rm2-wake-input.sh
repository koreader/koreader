#!/usr/bin/env bash

# While the reMarkable 2 is suspended, when the user presses the power button and wakes up the device,
# no events are sent to /dev/input/event0, so KOReader does not know that the system has woken up.
# As a workaround, copy this executable script into /lib/systemd/system-sleep
# Systemd will execute any scripts in that directory when the system's sleep state changes

if [[ "${1}" == "post" ]]; then # only run when sleep ENDS, not when sleep STARTS
    # simulate the same four events that are generated when the power button is pressed and released
    # (leaving event.time values at 0 for simplicity)

    # type: EV_KEY, code: 116 (power button), value: EV_PRESSED
    echo -n -e '\x00\x00\x00\x00\x00\x00\x00\x00\x01\x00\x74\x00\x01\x00\x00\x00' > /dev/input/event0

    # type: EV_SYN, code: SYN_REPORT, value: 0
    echo -n -e '\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00' > /dev/input/event0

    # type: EV_KEY, code: 116 (power button), value: EV_RELEASED
    echo -n -e '\x00\x00\x00\x00\x00\x00\x00\x00\x01\x00\x74\x00\x00\x00\x00\x00' > /dev/input/event0

    # type: EV_SYN, code: SYN_REPORT, value: 0
    echo -n -e '\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00' > /dev/input/event0
fi


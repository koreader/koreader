#!/usr/bin/env bash

# inspired by https://gist.github.com/nicolasazrak/32d68ed6c845a095f75f037ecc2f0436

# Takes two arguments:
# $1 arguments to pass to pgrep
# $2 process name to pgrep for
function gnuplot_wrapper() {
    TEMP_DIR="$(mktemp --directory /tmp/tmp.koreaderXXX)"
    LOG="${TEMP_DIR}/memory.log"
    SCRIPT_PNG="${TEMP_DIR}/script_png.p"
    SCRIPT_SHOW="${TEMP_DIR}/script_show.p"
    IMAGE_PNG="${TEMP_DIR}/graph.png"

    echo "Memory plot output to ${TEMP_DIR}"

    cat >"${SCRIPT_PNG}" <<EOL
set term pngcairo size 1600,1200
set output "${IMAGE_PNG}"
set ylabel "RSS"
set y2label "VSZ"
set ytics nomirror
set y2tics nomirror in
set yrange [0:*]
set y2range [0:*]
plot "${LOG}" using 3 with lines axes x1y1 title "RSS", "${LOG}" using 2 with lines axes x1y2 title "VSZ"
EOL

    # Launch program.
    "$@" &
    PROG_PID=$!
    trap 'kill "${PROG_PID}"' INT

    # Initialize at 0 so gnuplot has something to show.
    echo "0 0 0" >"${LOG}"
    gnuplot "${SCRIPT_SHOW}" &
    GNUPLOT_PID=$!

    cat >"${SCRIPT_SHOW}" <<EOL
set term qt noraise
set ylabel "RSS"
set y2label "VSZ"
set ytics nomirror
set y2tics nomirror in
set yrange [0:*]
set y2range [0:*]
while (1) {
  plot "${LOG}" using 3 with lines axes x1y1 title "RSS", "${LOG}" using 2 with lines axes x1y2 title "VSZ"
  pause 1
  system("ps -p ${PROG_PID} -o pid= >/dev/null 2>&1")
  if (GPVAL_SYSTEM_ERRNO != 0) {
    break
  }
}
EOL

    while ps -p "${PROG_PID}" -o pid=,vsz=,rss= >>"${LOG}"; do
        sleep 1
    done
    wait ${GNUPLOT_PID}

    gnuplot "${SCRIPT_PNG}"
}

gnuplot_wrapper "$@"

# vim: sw=4

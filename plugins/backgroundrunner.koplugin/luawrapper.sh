#!/bin/sh

# Converts the return of "sh wrapper.sh $@" into Lua format.

CURRENT_DIR=dirname "$0"
sh $CURRENT_DIR/wrapper.sh $@ &
JOB_ID=$!

while true
do
  ps -p $JOB_ID | grep $JOB_ID > /dev/null 2>&1
  if [ $? ]
  then
    # Unblock f:read().
    echo
  else
    wait $JOB_ID
    EXIT_CODE=$?
    if [ "$EXIT_CODE" -eq "255" ]
    then
      TIMEOUT="true"
    else
      TIMEOUT="false"
    fi

    if [ "$EXIT_CODE" -eq "127" ]
    then
      BADCOMMAND="true"
    else
      BADCOMMAND="false"
    fi

    echo "{ result = $EXIT_CODE, timeout = $TIMEOUT, badcommand = $BADCOMMAND }"
  fi
done

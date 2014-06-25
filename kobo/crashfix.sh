#!/bin/sh
i = 0
while :
do
    echo $i > test.log
    sleep 1
done
echo "Done" >> test.log

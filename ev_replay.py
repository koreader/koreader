#!/usr/bin/env python
# -*- coding:utf-8 -*-

import pprint
import struct
import argparse

EV_LOG = "ev_double.log"
EV_PIPE = "emu_event"

def gen_ev_from_log_entry(line):
    values = line.split("|")
    return {
        "time": {
            "sec": int(values[3]),
            "usec": int(values[4]),
            },
        "type": int(values[0]),
        "code": int(values[1]),
        "value": int(values[2]),
        }

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("ev_log", type=str,
            help="event log file to replay")
    args = parser.parse_args()

    # parse ev log into dictionaries
    evs = [gen_ev_from_log_entry(line.strip())
            for line in open(args.ev_log)]
    #pprint.pprint(evs)

    # replay evs
    ev_pipe = open(EV_PIPE, "w")
    for ev in evs:
        #@TODO also simulate timing here  25.02 2013 (houqp)
        ev_pipe.write(
            struct.pack("llHHi", 
                ev["time"]["sec"], ev["time"]["usec"],
                ev["type"],
                ev["code"],
                ev["value"])
            )




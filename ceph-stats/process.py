#!/usr/bin/env python

import json
import os
import re
import sys
import time

#
# Global
#

CEPHSTATS_LOG_FILE = os.environ.get('CEPHSTATS_LOG_FILE') or \
                     "/var/log/ceph/ceph-stats.%s.log" % (time.strftime("%F"))

#
# Functions
#

def usage():
    sys.stderr.write("usage: %s <name> [<key>]\n" % (sys.argv[0]))
    exit(1)

def main():
    if len(sys.argv) < 2:
        usage()
    name = sys.argv[1]
    key  = sys.argv[2:]
    f = open(CEPHSTATS_LOG_FILE, 'r')
    r = re.compile('^(\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d) \[%s\] \s*(.*)$' % (name))
    for line in f:
        m = r.match(line)
        if not m:
            continue
        t = m.group(1)
        v = json.loads(m.group(2))
        for k in key:
            if k.isdigit():
                k = int(k)
            v = v[k]
        print t, v

main()

#!/usr/bin/env python3
#
# List replica/shards of inactive PGs per OSD.
#


import json
import os
import subprocess
import sys

dump = json.loads(
    subprocess.check_output(
        ['ceph', 'pg', 'dump_stuck', 'inactive', '--format=json'],
        stderr=subprocess.DEVNULL
    ).decode('utf-8')
)

osds = {}

for pg in dump['stuck_pg_stats']:
    pgid = pg['pgid']
    query = json.loads(
        subprocess.check_output(
            ['ceph', 'pg', pgid, 'query']
        ).decode('utf-8')
    )
    if 'recovery_state' not in query:
        continue
    for s in query['recovery_state']:
        if 'past_intervals' not in s:
            continue
        for interval in s['past_intervals']:
            if 'all_participants' not in interval:
                continue
            for p in interval['all_participants']:
                osd = p['osd']
                if osd not in osds:
                    osds[osd] = set()
                if 'shard' in p:
                    osds[osd].add(f'{pgid}s{p["shard"]}')
                else:
                    osds[osd].add(f'{pgid}')

for osd in sorted(osds.keys()):
    print(f'osd.{osd}: {" ".join(sorted(osds[osd]))}')

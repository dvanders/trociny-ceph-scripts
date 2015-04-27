#!/bin/sh

LANG=C

PERIOD=1
COUNT=

miostat()
{
    local t=$1
    local c=$2
    local date

    while true
    do
	date=`date '+%F %T %s'`
	cat /proc/diskstats | sed -e "s/^/${date} /g"
	if [ -n "$c" ]
	then
	    c=$((c -1))
	    if [ "$c" -eq 0 ]
	    then
		break
	    fi
	fi
	sleep $t || break
    done
}

#
# Main
#

(
    uname -a
    echo
    mount
    echo
    df -hT
    echo
    ls /var/lib/ceph/*
    echo
    ls -l /var/lib/ceph/osd/ceph-*/journal
    echo
    du -hs /var/lib/ceph/mon/ceph-node-*/store.db
    echo
    ceph-disk list
    echo
    ps auxww |grep -E '^USER|[c]eph-(mon|osd|mds)'
    echo

) 2>&1 | sed -e 's/^/# /g'


if [ -n "$1" ]
then
    PERIOD=$1
fi

if [ -n "$2" ]
then
    COUNT=$2
fi

miostat "${PERIOD}" "${COUNT}"

#!/bin/sh

usage()
{
    echo "usage: $0 set|unset osd.* mon.* ... " >&2
    exit 1
}

if [ "$1" != set -a "$1" != "unset" ]
then
    usage
fi

op=$1 ; shift

for d
do
    case "$d" in
	mon.*)
	    if [ "$op" = set ]
	    then
		ceph tell "$d" injectargs '--debug-mon 10' '--debug-paxos 10' '--debug-ms 1'
	    else
		ceph tell "$d" injectargs '--debug-mon 1/5' '--debug-paxos 1/5' '--debug-ms 0/5'
	    fi
	    ;;
	osd.*)
	    if [ "$op" = set ]
	    then
		ceph tell "$d" injectargs '--debug-osd 10'
	    else
		ceph tell "$d" injectargs '--debug-osd 0/5'
	    fi
	    ;;
	*)
	    usage
	    ;;
    esac
done

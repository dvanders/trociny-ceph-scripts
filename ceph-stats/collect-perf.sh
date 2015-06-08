#!/bin/sh

#
# Globals
#

# Log file

: ${CEPH_LOG_DIR:='/var/log/ceph'}
: ${CEPHPERF_LOG_DIR:=${CEPH_LOG_DIR}}
: ${CEPHPERF_LOG_FILE:=${CEPHPERF_LOG_DIR}/'ceph-stats.{DAEMON}.perf.{DATE}.log'}

#
# Functions
#

usage()
{
    echo "usage: $0 osd.X|mon.X [interval [count]]" >&2
    exit 1
}

get_arg()
{
    case $1 in
	"")
	    echo -1
	    ;;
	[0-9]*)
	    echo $1
	    ;;
	*)
	    usage
	    ;;
    esac
}

logfile()
{
    local daemon=$1
    local cmd=$2
    local date

    if [ "$#" -gt 2 ]
    then
	date="$3"
    else
	date=$(date '+%F')
    fi

    printf "%s" "${CEPHPERF_LOG_FILE}" | sed -e "s/{DAEMON}/${daemon}/g; s/{CMD}/${cmd}/g; s/{DATE}/${date}/g;"
}

collect()
{
    local daemon=$1
    local cmd

    (
	printf "%s [perf] " "$(date '+%F %T')"
	ceph -f json daemon ${daemon} perf dump
    ) >> "$(logfile ${daemon})"
}

main()
{
    local daemon=$1
    local interval=$(get_arg $2)
    local count=$(get_arg $3)

    test -n "${daemon}" || usage
    
    collect ${daemon}

    if [ ${interval} -lt 0 ]
    then
	return
    fi

    if [ $count -ge 0 ]
    then
	local i

	test $count -le 1 && return

	for i in `seq $((count - 1))`
	do
	    sleep ${interval} || return
	    collect ${daemon}
	done
	return
    fi

    while sleep ${interval}
    do
	collect ${daemon}
    done
}

#
# Main
#

main $@

#!/bin/sh

#
# Globals
#

# Ceph stats commands to run

CEPHSTATS_CMD_status='ceph -f json status'
CEPHSTATS_CMD_health='ceph -f json health detail'
CEPHSTATS_CMD_osddump='ceph -f json osd dump'
CEPHSTATS_CMD_poolstats='ceph -f json osd pool stats'
CEPHSTATS_CMD_df='ceph -f json df'

# Log file

: ${CEPHSTATS_LOG_FILE:=/var/log/ceph/ceph-stats.$(date '+%F').log}

: ${CEPHSTATS_LOG_ROTATE_FILE_GLOB:='/var/log/ceph/ceph-stats.*.log'}
: ${CEPHSTATS_LOG_ROTATE_DAYS:=7}

#
# Functions
#

list_vars()
{
    local line var

    set |
    while read line
    do
        var="${line%%=*}"
        case "${var}" in
            "${line}"|*[!a-zA-Z0-9_]*)
		continue
		;;
            $1)
		echo ${var}
		;;
	esac
    done
}

usage()
{
    echo "usage: $0 [interval]"                                              >&2
    echo ""                                                                  >&2
    echo "Collect Ceph statistics to ${CEPHSTATS_LOG_FILE}"                  >&2
    echo "running the following commands:"                                   >&2
    echo ""                                                                  >&2
    for var in $(list_vars 'CEPHSTATS_CMD_*')
    do
	printf "  %-14s%s\n" "${var##CEPHSTATS_CMD_}:" "$(eval echo '$'${var})"
    done                                                                     >&2
    echo ""                                                                  >&2
    echo "Log files older ${CEPHSTATS_LOG_ROTATE_DAYS} days are rotated."    >&2
    echo ""                                                                  >&2
    exit 1
}

rotate()
{
    local f

    for f in `eval echo $GLOB`
    do
	test -f "${f}" || continue
	find "${f}" -mtime -"${CEPHSTATS_LOG_ROTATE_DAYS}" -exec rm {} \;
    done
}

collect()
{
    local cmd name var

    for var in $(list_vars 'CEPHSTATS_CMD_*')
    do
	name=${var##CEPHSTATS_CMD_}
	cmd=$(eval echo '$'${var})
	printf "%s [%s] " "$(date '+%F %T')" "${name}"
	$cmd | sed '/^[[:space:]]*$/d'
    done >> ${CEPHSTATS_LOG_FILE}
}

main()
{
    local interval=-1

    case $1 in
	"")
	    ;;
	[0-9]*)
	    interval=$1
	    ;;
	*)
	    usage
	    ;;
    esac

    rotate
    collect

    test ${interval} -lt 0 && return

    while sleep ${interval}
    do
	rotate
	collect
    done
}


#
# Main
#

main $@

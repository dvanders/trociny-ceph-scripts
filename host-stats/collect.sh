#!/bin/sh

#
# Globals
#

LANG=C

# Stats commands to run

HOSTSTATS_CMD_top='top -b -d {PERIOD} -n {COUNT}'
HOSTSTATS_CMD_diskstats='hoststats_diskstats {PERIOD} {COUNT}'
HOSTSTATS_CMD_iostat='iostat -x -t -p {PERIOD} {COUNT}'
HOSTSTATS_CMD_netstat_i='hoststats_netstat_i {PERIOD} {COUNT}'
HOSTSTATS_CMD_netstat_s='hoststats_netstat_s {PERIOD} {COUNT}'
HOSTSTATS_CMD_vmstat='hoststats_vmstat {PERIOD} {COUNT}'

# Log file

: ${HOSTSTATS_LOG_FILE:='/var/log/ceph/ceph-stats.{CMD}.{DATE}.log'}
: ${HOSTSTATS_LOG_ROTATE_DAYS:=7}

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

logfile()
{
    local cmd=$1
    local date

    if [ "$#" -gt 1 ]
    then
	date="$2"
    else
	date=$(date '+%F')
    fi

    printf "%s" "${HOSTSTATS_LOG_FILE}" | sed -e "s/{CMD}/${cmd}/g; s/{DATE}/${date}/g;"
}

usage()
{
    echo "usage: $0 [interval]"                                              >&2
    echo ""                                                                  >&2
    echo "Collect Ceph statistics to ${HOSTSTATS_LOG_FILE}"                  >&2
    echo "running the following commands:"                                   >&2
    echo ""                                                                  >&2
    for var in $(list_vars 'HOSTSTATS_CMD_*')
    do
	printf "  %-14s%s\n" "${var##HOSTSTATS_CMD_}:" "$(eval echo '$'${var})"
    done                                                                     >&2
    echo ""                                                                  >&2
    echo "Log files older ${HOSTSTATS_LOG_ROTATE_DAYS} days are rotated."    >&2
    echo ""                                                                  >&2
    exit 1
}

rotate()
{
    local f name var

    for var in $(list_vars 'HOSTSTATS_CMD_*')
    do
	name=${var##HOSTSTATS_CMD_}
	for f in `eval echo $(logfile ${name} '*')`
	do
	    test -f "${f}" || continue
	    find "${f}" -type f -mtime +"${HOSTSTATS_LOG_ROTATE_DAYS}" -exec rm {} \;
	done
    done
}

collect()
{
    local period=$1
    local count=$2
    local cmd name var

    for var in $(list_vars 'HOSTSTATS_CMD_*')
    do
	name=${var##HOSTSTATS_CMD_}
	cmd=$(eval echo '$'${var} | sed "s/{PERIOD}/${period}/g; s/{COUNT}/${count}/g;")
	$cmd >> "$(logfile ${name})" 2>&1 &
    done
    trap "pkill -P $$" INT TERM
    wait
}

main()
{
    rotate
    collect $@
}

#
# Custom stats commands
#

hoststats_cmd()
{
    local t=$1 ; shift
    local c=$1 ; shift
    local cmd
    local date

    cmd="$@"
    while true
    do
	date=`date '+%F %T %s'`
	${cmd} | sed -e "s/^/${date} /g"
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

hoststats_diskstats()
{
    hoststats_cmd $@ cat /proc/diskstats
}

hoststats_netstat_i()
{
    hoststats_cmd $@ netstat -ni
}

hoststats_netstat_s()
{
    hoststats_cmd $@ netstat -s
}

hoststats_vmstat()
{
    local date line

    vmstat $@ |
    while read line
    do
	date=`date '+%F %T %s'`
	printf "%s %s\n" "${date}" "${line}"
    done
}

#
# Main
#

period=1
count=1

if [ -n "$1" ]
then
    period=$1
fi

if [ -n "$2" ]
then
    count=$2
fi

main "${period}" "${count}"

#!/bin/sh

#
# Globals
#

# Report commands to run

HOSTREPORT_CMD_ntp='ntpdc -p'
HOSTREPORT_CMD_dmesg='dmesg'
HOSTREPORT_CMD_vmstat_s='vmstat -s'
HOSTREPORT_CMD_vmstat_m='vmstat -m'

# Log file

: ${HOSTREPORT_LOG_FILE:='/var/log/ceph/ceph-report.{CMD}.{DATE}.log'}

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

    printf "%s" "${HOSTREPORT_LOG_FILE}" | sed -e "s/{CMD}/${cmd}/g; s/{DATE}/${date}/g;"
}

collect()
{
    local cmd name var

    for var in $(list_vars 'HOSTREPORT_CMD_*')
    do
	name=${var##HOSTREPORT_CMD_}
	cmd=$(eval echo '$'${var})
	echo "[$(date '+%F %T')] ${name}:" >> "$(logfile ${name})"
	$cmd >> "$(logfile ${name})" 2>&1
    done
}

main()
{
    collect
}

#
# Main
#

main

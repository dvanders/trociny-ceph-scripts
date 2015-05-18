#!/bin/sh

#
# Globals
#

# Report commands to run

CEPHREPORT_MON_CMD_version='version'
CEPHREPORT_MON_CMD_config='config show'
CEPHREPORT_MON_CMD_status='mon_status'
CEPHREPORT_MON_CMD_perf='perf dump'

CEPHREPORT_OSD_CMD_version='version'
CEPHREPORT_OSD_CMD_config='config show'
CEPHREPORT_OSD_CMD_status='status'
CEPHREPORT_OSD_CMD_op_pq_state='dump_op_pq_state'
CEPHREPORT_OSD_CMD_watchers='dump_watchers'
CEPHREPORT_OSD_CMD_blacklist='dump_blacklist'
CEPHREPORT_OSD_CMD_ops_in_flight='dump_ops_in_flight'
CEPHREPORT_OSD_CMD_historic_ops='dump_historic_ops'
CEPHREPORT_OSD_CMD_perf='perf dump'

# Log file

: ${CEPH_LOG_DIR:='/var/log/ceph'}
: ${CEPHREPORT_LOG_DIR:=${CEPH_LOG_DIR}}
: ${CEPHREPORT_LOG_FILE:=${CEPHREPORT_LOG_DIR}/'ceph-report.{DAEMON}.{CMD}.{DATE}.log'}

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
    local daemon=$1
    local cmd=$2
    local date

    if [ "$#" -gt 2 ]
    then
	date="$3"
    else
	date=$(date '+%F')
    fi

    printf "%s" "${CEPHREPORT_LOG_FILE}" | sed -e "s/{DAEMON}/${daemon}/g; s/{CMD}/${cmd}/g; s/{DATE}/${date}/g;"
}

usage()
{
    echo "usage: $0 osd.X|mon.X" >&2
    exit 1
}

collect()
{
    local daemon=$1
    local cmd name vars var

    case "${daemon}" in
	mon.*)
	    vars='CEPHREPORT_MON_CMD_'
	    ;;
	osd.*)
	    vars='CEPHREPORT_OSD_CMD_'
	    ;;
	*)
	    usage
	    ;;
    esac

    for var in $(list_vars "${vars}*")
    do
	name=${var##${vars}}
	cmd=$(eval echo ceph daemon ${daemon} '$'${var})
	echo "[$(date '+%F %T')] ${name}:" >> "$(logfile ${daemon} ${name})"
	$cmd >> "$(logfile ${daemon} ${name})" 2>&1
    done
}

main()
{
    collect $@
}

#
# Main
#

main $@

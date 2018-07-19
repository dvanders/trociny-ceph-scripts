#!/bin/sh

#
# Globals
#

: ${CEPH_SCRIPTS_DIR:=$(readlink -f $(dirname $0))}


#
# Functions
#


list_daemons()
{
    ps auxww | sed -nEe 's/^.*ceph-(mds|mgr|mon|osd) .*-id? *([^ ]*) .*/\1.\2/p'
}


main()
{
    local d

    trap "pkill -P $$" INT TERM

    for d in $(list_daemons)
    do
	${CEPH_SCRIPTS_DIR}/collect-perf.sh ${d} "$@"&
    done

    wait
}

#
# Main
#

main "$@"

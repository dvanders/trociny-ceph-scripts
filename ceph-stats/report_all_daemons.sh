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
    ps auxww |sed -nEe 's/^.*ceph-(mon|osd) .*-i *([^ ]*) .*/\1.\2/p'
}


main()
{
    local d

    for d in $(list_daemons)
    do
	${CEPH_SCRIPTS_DIR}/report.sh ${d}
    done
}

#
# Main
#

main

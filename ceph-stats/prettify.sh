#!/bin/sh

#
# Globals
#

# Log file

: ${CEPH_LOG_DIR:='/var/log/ceph'}
: ${CEPHSTATS_DATE:=$(date '+%F')}
: ${CEPHSTATS_LOG_DIR:=${CEPH_LOG_DIR}}
: ${CEPHSTATS_LOG_FILE:="${CEPHSTATS_LOG_DIR}/ceph-stats.${CEPHSTATS_DATE}.log"}
: ${CEPHSTATS_LOG_ROTATE_DAYS:=7}

#
# Main
#

# 2015-05-04 15:59:10 [df] {"stats":{...
if [ -n "$1" ]
then
    awk '$3 == "['"${1}"']"' ${CEPHSTATS_LOG_FILE}
else
    cat ${CEPHSTATS_LOG_FILE}
fi |
while read date time name data
do
    echo -n "${date} ${time} ${name} "
    echo "${data}" | json_pp
done
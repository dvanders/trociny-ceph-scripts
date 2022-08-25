#!/bin/sh -xe

NWORKERS=16
DATAPOOL=cephfs_data
CEPHFS=storage

# alias cephfs-table-tool="echo cephfs-table-tool"
# alias cephfs-journal-tool="echo cephfs-journal-tool"
# alias cephfs-data-scan="echo cephfs-data-scan"

#
# Functions
#

cephfs_data_scan() {
    test -n "$1"
    local cmd="$1"

    test -n "$2"
    local worker="$2"

    cephfs-data-scan "${cmd}" --worker_n "${worker}" --worker_m "${NWORKERS}" \
		     --filesystem "${CEPHFS}" "${DATAPOOL}"  2>&1 |
	tee cephfs-data-scan."${cmd}"."${worker}".log
    echo "${cmd} ${worker} complete" >&2
}

scan_extents() {
    test -n "$1"

    local worker="$1"

    cephfs_data_scan scan_extents "${worker}"
}

scan_inodes() {
    test -n "$1"

    local worker="$1"

    cephfs_data_scan scan_inodes "${worker}"
}


#
# Main
#

test -n "$1" && NWORKERS="$1"
test ${NWORKERS} -gt 0 -a ${NWORKERS} -le 512

cephfs-table-tool 0 reset session
cephfs-table-tool 0 reset snap
cephfs-table-tool 0 reset inode
cephfs-journal-tool --rank=${CEPHFS}:0 journal reset

cephfs-data-scan init

echo "SCANNING EXTENTS" >&2

for worker in `seq 0 $((NWORKERS - 1))`; do
    scan_extents ${worker} &
done

wait
echo "SCANNING EXTENTS DONE" >&2

echo "SCANNING INODES" >&2

for worker in `seq 0 $((NWORKERS - 1))`; do
    scan_inodes ${worker} &
done

wait
echo "SCANNING INODES DONE" >&2

echo "SCANNING LINKS" >&2
cephfs-data-scan scan_links
echo "SCANNING LINKS DONE" >&2

echo "CLEANUP" >&2
cephfs-data-scan cleanup "${DATAPOOL}"

echo "OK" >&2

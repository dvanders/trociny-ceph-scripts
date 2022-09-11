#!/bin/sh -e
#
# This script will recover cephfs missing metada from data objects
# using a procedure described in:
#
# https://docs.ceph.com/en/quincy/cephfs/disaster-recovery-experts/#recovery-from-missing-metadata-objects
#

#
# Globals
#
CEPHFS=
DATAPOOL=
NRANKS=1
NWORKERS=16

#
# Uncomment for NOP testing:
#
# alias cephfs-table-tool="echo cephfs-table-tool"
# alias cephfs-journal-tool="echo cephfs-journal-tool"
# alias cephfs-data-scan="echo cephfs-data-scan"

#
# Functions
#
usage() {
    echo "$0 <cephfs> [nranks [nworkers]]"
}

get_datapool() {
    # TODO: support multiple data pools
    DATAPOOLID=$(ceph fs get ${CEPHFS} |
		     sed -nEe 's/^data_pools[ \t]*\[([0-9]*)].*/\1/p')
    test -n "${DATAPOOLID}" -a "${DATAPOOLID}" -gt 0

    DATAPOOL=$(ceph df | awk '$2 == '${DATAPOOLID}' {print $1}')
    test -n "${DATAPOOL}"
}

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

case $1 in
    "-h|--help")
	usage
	exit 0
        ;;
    "")
	usage >&2
	exit 1
        ;;
    *)
        CEPHFS=$1
        ;;
esac

# TODO: improve logging so we don't need to use `set -x`
set -x

test -n "$2" && NRANKS="$2"
test ${NRANKS} -gt 0

test -n "$3" && NWORKERS="$3"
test ${NWORKERS} -gt 0 -a ${NWORKERS} -le 512

get_datapool

echo "INITIALIZING METADATA" >&2

for rank in `seq 0 $((NRANKS - 1))`; do
    # Reset session table
    cephfs-table-tool ${CEPHFS}:${rank} reset session

    # reset SnapServer
    cephfs-table-tool ${CEPHFS}:${rank} reset snap

    # reset InoTable
    cephfs-table-tool ${CEPHFS}:${rank} reset inode

    # reset journal
    cephfs-journal-tool --rank=${CEPHFS}:${rank} journal reset
done

# Regenareate root inodes ("/" and MDS directory) if missing
cephfs-data-scan init --filesystem "${CEPHFS}"

echo "INITIALIZING METADATA DONE" >&2

echo "SCANNING EXTENTS" >&2

# List all inode objects (named as {inode}.{index}) in the data pool
# and accumulate collected inode information in {inode}.0 object
# attributes:
#   * the highest inode object index seen and its size ("scan_ceiling" xattr)
#   * the largest inode object seen ("scan_max_size")
#   * the highest inode object mtime seen ("scan_max_mtime" xattr)
#
# This information will be used on the next stepts to infer the object
# chunking size, the offset of the last object (chunk size * highest
# index seen), the actual size (offset of last object + size of
# highest ID seen), and the inode mtime
#
# NOTE: this logic doesn't take account of striping.
#
for worker in `seq 0 $((NWORKERS - 1))`; do
    scan_extents ${worker} &
done

wait
echo "SCANNING EXTENTS DONE" >&2

echo "SCANNING INODES" >&2

# Scan all {inode}.0 objects in the data pool, fetching previously
# accumulated data ("scan_ceiling", "scan_max_size", and
# "scan_max_mtime" xattrs), layout and backtrace data ("layout" and
# "parent" xattrs). Using this information rebuild (create or update)
# inode metadata in the metadata pool. Put strays and inodes without
# backtrace in lost+found.
for worker in `seq 0 $((NWORKERS - 1))`; do
    scan_inodes ${worker} &
done

wait
echo "SCANNING INODES DONE" >&2

echo "SCANNING LINKS" >&2

# Check inode linkages and fix found error. On the first step
# (SCAN_INOS) all inodes in metadata pool are scanned. If it is a
# dirfrag inode, its entries are read to detect dups. If it is a link
# inode, the ref count is increased for the inode it reffers to.  On
# the second step (CHECK_LINK) it resolves found dups and other
# inconsitencies.
cephfs-data-scan scan_links --filesystem "${CEPHFS}"

echo "SCANNING LINKS DONE" >&2

echo "CLEANUP" >&2

# Delete ancillary data generated during recovery (xattrs).
cephfs-data-scan cleanup --filesystem "${CEPHFS}" "${DATAPOOL}"

echo "OK" >&2

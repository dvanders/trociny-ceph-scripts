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
METADATAPOOL=
DATAPOOL=
NRANKS=1
NWORKERS=16
WAIT_SLEEP_INTERVAL=10
LOGDIR=recover_metadata_logs
: ${PROCESS_SCAN_LINK_LOG:=}

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

check_deps() {
    if ! which jq >/dev/null 2>&1; then
	echo 'jq is not installed' >&2
	return 1
    fi
}

prepare_log_dir() {
    test -n "${LOGDIR}"

    mkdir -p "${LOGDIR}"
    rm -f "${LOGDIR}"/*.log "${LOGDIR}"/*.dat
}

get_metadatapool() {
    # TODO: support multiple data pools
    METADATAPOOLID=$(ceph fs get ${CEPHFS} --format json |
			 jq '.mdsmap.metadata_pool')
    if ! [ -n "${METADATAPOOLID}" -a "${METADATAPOOLID}" -gt 0 ]; then
	echo "failed to get metadatapoolid for fs ${CEPHFS}: ${METADATAPOOLID}" 2>&2
	return 1
    fi

    METADATAPOOL=$(ceph df | awk '$2 == '${METADATAPOOLID}' {print $1}')
    if ! [ -n "${METADATAPOOL}" ]; then
	echo "failed to get datapool for datapoolid ${METADATAPOOLID}" 2>&2
	return 1
    fi
}

get_datapool() {
    # TODO: support multiple data pools
    DATAPOOLID=$(ceph fs get ${CEPHFS} --format json | jq '.mdsmap.data_pools[]')
    if ! [ -n "${DATAPOOLID}" -a "${DATAPOOLID}" -gt 0 ]; then
	echo "failed to get datapoolid for fs ${CEPHFS}: ${DATAPOOLID}" 2>&2
	return 1
    fi

    DATAPOOL=$(ceph df | awk '$2 == '${DATAPOOLID}' {print $1}')
    if ! [ -n "${DATAPOOL}" ]; then
	echo "failed to get datapool for datapoolid ${DATAPOOLID}" 2>&2
	return 1
    fi
}

cephfs_data_scan() {
    test -n "$1"
    local cmd="$1"

    test -n "$2"
    local worker="$2"

    cephfs-data-scan "${cmd}" --worker_n "${worker}" --worker_m "${NWORKERS}" \
		     --filesystem "${CEPHFS}" --debug-mds 10 "${DATAPOOL}" 2>&1 |
	tee "${LOGDIR}"/cephfs-data-scan."${cmd}"."${worker}".log
    echo "${cmd} ${worker} complete" >&2
}

scan_extents() {
    test -n "$1"

    local worker="$1"

    cephfs_data_scan scan_extents "${worker}" |
    awk -v f=${LOGDIR}/num_scan_extents.${worker}.dat \
	-v f0=${LOGDIR}/num_0_scan_extents.${worker}.dat \
    '
        BEGIN {
            n = n0 = 0
            print(n) > f; close(f)
            print(n0) > f0; close(0)
        }

        /handling object/ {
            n++
        }

        /handling object [0-9a0-f]*\.0$/ {
                n0++
        }

        n % 1000 == 0 {
            print(n) > f; close(f)
            print(n0) > f0; close(f0)
        }

        END {
            print(n) > f; close(f)
            print(n0) > f0; close(f0)
        }
    '
}

scan_inodes() {
    test -n "$1"

    local worker="$1"

    cephfs_data_scan scan_inodes "${worker}" |
    awk -v f=${LOGDIR}/num_scan_inodes.${worker}.dat \
    '
        BEGIN {
            n = 0
            print(n) > f; close(f)
        }

        /handling object/ {
            n++
        }

        n % 1000 == 0 {
            print(n) > f; close(f)
        }

        END {
            print(n) > f; close(f)
        }
    '
}

scan_links() {
    cephfs-data-scan scan_links --filesystem "${CEPHFS}" --debug-mds 10 2>&1 |
    tee "${LOGDIR}"/cephfs-data-scan.scan_links.0.log |
    awk -v f=${LOGDIR}/num_scan_links.0.dat \
	-v d=${LOGDIR}/num_scan_links_dups.dat \
	-v r=${LOGDIR}/num_scan_links_rem_dups.dat \
	-v b=${LOGDIR}/num_scan_links_bad.dat \
	-v i=${LOGDIR}/num_scan_links_injected.dat \
    '
        BEGIN {
            n = 0
            print(n) > f; close(f)
        }

        /handling object/ {
            n++
        }

        n % 1000 == 0 {
            print(n) > f; close(f)
        }

        /processing .* dup_primaries/ {
            print(n) > f; close(f)
	    sub(/^.*datascan.scan_links: /, "")
	    print > d; close(d)
        }

	/removing dup dentries/ {
	    sub(/^.*datascan.scan_links: /, "")
	    print > r; close(r)
	}

	/processing .* bad_nlink_inos/ {
	    sub(/^.*datascan.scan_links: /, "")
	    print > b; close(b)
	}

	/processing .* injected_inos/ {
	    sub(/^.*datascan.scan_links: /, "")
	    print > i; close(i)
	}
    '
}

wait_scan_extents_complete() {
    local objnum sobjnum

    objnum=$(ceph df --format json |
		 jq -r '.pools[] | select(.name == "'${DATAPOOL}'").stats.objects')

    if [ -z "${objnum}" ] || [ "${objnum}" -eq 0 ]; then
	wait
	return
    fi

    while sleep ${WAIT_SLEEP_INTERVAL}; do
	sobjnum=$(awk '{s += $1} END{print s}' "${LOGDIR}"/num_scan_extents.*.dat)
	test -n "${sobjnum}" || sobjnum=0
	echo "${sobjnum}/${objnum} objects ($((100 * sobjnum / objnum))%) processed" >&2

	jobs > "${LOGDIR}"/jobs
	test $(wc -l < "${LOGDIR}"/jobs) -eq 0 && break
    done
}

wait_scan_inodes_complete() {
    local objnum sobjnum

    objnum=$(awk '{s += $1} END{print s}' "${LOGDIR}"/num_0_scan_extents.*.dat)

    if [ -z "${objnum}" ] || [ "${objnum}" -eq 0 ]; then
	wait
	return
    fi

    while sleep ${WAIT_SLEEP_INTERVAL}; do
	sobjnum=$(awk '{s += $1} END{print s}' "${LOGDIR}"/num_scan_inodes.*.dat)
	test -n "${sobjnum}" || sobjnum=0
	echo "${sobjnum}/${objnum} objects ($((100 * sobjnum / objnum))%) processed" >&2

	jobs > "${LOGDIR}"/jobs
	test $(wc -l < "${LOGDIR}"/jobs) -eq 0 && break
    done
}

wait_scan_links_complete() {
    local objnum sobjnum
    local scan_done dup_done rem_dup_done bad_done

    test -n "${PROCESS_SCAN_LINK_LOG}" &&
    objnum=$(ceph df --format json |
		 jq -r '.pools[] | select(.name == "'${METADATAPOOL}'").stats.objects')

    if [ -z "${objnum}" ] || [ "${objnum}" -eq 0 ]; then
	wait
	return
    fi

    # scan_links scans metadata objects twice
    objnum=$((objnum * 2))

    while sleep ${WAIT_SLEEP_INTERVAL}; do
	if [ -n "${bad_done}" ]; then
	    test -f ${LOGDIR}/num_scan_links_injected.dat || continue
	    cat ${LOGDIR}/num_scan_links_injected.dat >&2
	    wait
	    break
	fi

	if [ -n "${rem_dup_done}" ]; then
	    if [ -f ${LOGDIR}/num_scan_links_bad.dat ]; then
		cat ${LOGDIR}/num_scan_links_bad.dat >&2
		bad_done=1
	    fi
	    continue
	fi

	if [ -n "${dup_done}" ]; then
	    if [ -f ${LOGDIR}/num_scan_links_rem_dups.dat ]; then
		cat ${LOGDIR}/num_scan_links_rem_dups.dat >&2
		rem_dup_done=1
	    fi
	    continue
	fi

	if [ -n "${scan_done}" ]; then
	    cat ${LOGDIR}/num_scan_links_dups.dat >&2
	    dup_done=1
	    continue
	fi

	sobjnum=$(awk '{s += $1} END{print s}' "${LOGDIR}"/num_scan_links.*.dat)
	test -n "${sobjnum}" || sobjnum=0
	echo "${sobjnum}/${objnum} objects ($((100 * sobjnum / objnum))%) processed" >&2

	if [ -f ${LOGDIR}/num_scan_links_dups.dat ]; then
	    scan_done=1
	fi
    done
}

#
# Main
#

check_deps

case $1 in
    --help|-h)
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

test -n "$2" && NRANKS="$2"
if ! [ ${NRANKS} -gt 0 ]; then
    echo "invalid nranks: ${NRANKS}" 2>&2
    usage >&2
    exit 1
fi

test -n "$3" && NWORKERS="$3"
if ! [ ${NWORKERS} -gt 0 -a ${NWORKERS} -le 512 ]; then
    echo "invalid nworkers: ${NWORKERS}" 2>&2
    usage >&2
    exit 1
fi

get_metadatapool
get_datapool
prepare_log_dir

echo "INITIALIZING METADATA" >&2

for rank in `seq 0 $((NRANKS - 1))`; do
    # Reset session table
    cephfs-table-tool ${CEPHFS}:${rank} reset session

    # reset SnapServer
    cephfs-table-tool ${CEPHFS}:${rank} reset snap

    # reset InoTable
    cephfs-table-tool ${CEPHFS}:${rank} reset inode

    # reset journal
    cephfs-journal-tool --rank=${CEPHFS}:${rank} journal reset --force
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
for worker in `seq 0 $((NWORKERS - 1))`; do
    scan_extents ${worker} &
done
wait_scan_extents_complete

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
wait_scan_inodes_complete

echo "SCANNING INODES DONE" >&2

echo "SCANNING LINKS" >&2

# Check inode linkages and fix found error. On the first step
# (SCAN_INOS) all inodes in metadata pool are scanned. If it is a
# dirfrag inode, its entries are read to detect dups. If it is a link
# inode, the ref count is increased for the inode it reffers to.  On
# the second step (CHECK_LINK) it resolves found dups and other
# inconsitencies.
scan_links &
wait_scan_links_complete

echo "SCANNING LINKS DONE" >&2

echo "CLEANUP" >&2

# Delete ancillary data generated during recovery (xattrs).
cephfs-data-scan cleanup --filesystem "${CEPHFS}" --debug-mds 10 "${DATAPOOL}" \
		 > "${LOGDIR}"/cephfs-data-scan.cleanup.0.log 2>&1

echo "OK" >&2

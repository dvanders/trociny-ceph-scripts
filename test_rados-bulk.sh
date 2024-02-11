#!/bin/bash -ex

POOL=test_rados_bulk
OBJECTS=${OBJECTS:-100}
TEMPDIR=
RADOS_BULK=./rados-bulk
WORKERS=${WORKERS:-4}
QUEUE_DEPTH=${QUEUE_DEPTH:-64}
RADOS_BULK_OPTS="--workers ${WORKERS} --queue-depth ${QUEUE_DEPTH}"

setup() {
    local num_objects bs obj

    TEMPDIR=$(mktemp -d)

    ceph osd pool ls | grep -q ${POOL} || ceph osd pool create ${POOL}

    rados -p ${POOL} ls > ${TEMPDIR}/objects.txt
    num_objects=$(cat ${TEMPDIR}/objects.txt | wc -l)

    if [ ${num_objects} -lt ${OBJECTS} ]; then
        for i in $(seq 1 $((OBJECTS - num_objects))); do
	    obj=object-$i
	    while grep -q "^$obj\$" ${TEMPDIR}/objects.txt; do
		obj=${obj}-$i
	    done

            bs=$((1024 * (1023 + RANDOM % 2) * (1 + RANDOM % 5)))
            dd if=/dev/random of=/tmp/otest_rados_bulk_object bs=${bs} count=1
            rados -p ${POOL} put $obj /tmp/otest_rados_bulk_object
            rm /tmp/otest_rados_bulk_object
        done
    else
        num_objects=$((num_objects - OBJECTS))
        rados -p ${POOL} ls | head -n ${num_objects} | while read obj; do
            rados -p ${POOL} rm $obj
        done
    fi
}

cleanup() {
    set +ex
    ceph osd pool delete ${POOL} ${POOL} --yes-i-really-really-mean-it
    test -n "${TEMPDIR}" && rm -rf ${TEMPDIR}
    TEMPDIR=
}

trap cleanup INT TERM EXIT

setup

rados -p ${POOL} ls > ${TEMPDIR}/objects.txt

${RADOS_BULK} ${RADOS_BULK_OPTS} -p ${POOL} stat \
	      --object-list ${TEMPDIR}/objects.txt

split -l $((OBJECTS / 2 + RANDOM % (OBJECTS / 100 + 1))) \
      ${TEMPDIR}/objects.txt ${TEMPDIR}/objects.txt-
test $(ls ${TEMPDIR}/objects.txt-* | wc -l) -eq 2
test -f ${TEMPDIR}/objects.txt-aa
test -f ${TEMPDIR}/objects.txt-ab

${RADOS_BULK} ${RADOS_BULK_OPTS} -p ${POOL} stat \
	      --object-list ${TEMPDIR}/objects.txt

mkdir -p ${TEMPDIR}/objects

${RADOS_BULK} ${RADOS_BULK_OPTS} -p ${POOL} get \
	      --object-list ${TEMPDIR}/objects.txt-aa \
	      --object-dir ${TEMPDIR}/objects

test $(ls ${TEMPDIR}/objects | wc -l) -eq $(cat ${TEMPDIR}/objects.txt-aa | wc -l)
sort ${TEMPDIR}/objects.txt-aa > ${TEMPDIR}/objects.txt-aa.sorted
ls ${TEMPDIR}/objects | sort > ${TEMPDIR}/objects.sorted
cmp ${TEMPDIR}/objects.txt-aa.sorted ${TEMPDIR}/objects.sorted

for obj in $(ls ${TEMPDIR}/objects); do
    rados -p ${POOL} get $obj ${TEMPDIR}/object
    cmp ${TEMPDIR}/objects/$obj ${TEMPDIR}/object
    rm ${TEMPDIR}/object
done

${RADOS_BULK} ${RADOS_BULK_OPTS} -p ${POOL} rm \
	      --object-list ${TEMPDIR}/objects.txt-aa

rados -p ${POOL} ls > ${TEMPDIR}/objects.1.txt
cmp ${TEMPDIR}/objects.1.txt ${TEMPDIR}/objects.txt-ab

${RADOS_BULK} ${RADOS_BULK_OPTS} -p ${POOL} stat \
	      --object-list ${TEMPDIR}/objects.txt-aa 2>&1 |
    tee ${TEMPDIR}/stat.log

test $(grep -c 'not found' ${TEMPDIR}/stat.log) -eq \
     $(cat ${TEMPDIR}/objects.txt-aa | wc -l)

${RADOS_BULK} ${RADOS_BULK_OPTS} -p ${POOL} put \
	      --object-dir ${TEMPDIR}/objects

rados -p ${POOL} ls > ${TEMPDIR}/objects.2.txt
cmp ${TEMPDIR}/objects.2.txt ${TEMPDIR}/objects.txt

for obj in $(ls ${TEMPDIR}/objects); do
    rados -p ${POOL} get $obj ${TEMPDIR}/object
    cmp ${TEMPDIR}/objects/$obj ${TEMPDIR}/object
    rm ${TEMPDIR}/object
done

echo OK

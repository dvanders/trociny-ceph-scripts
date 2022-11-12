#!/bin/sh -e
#
# The script can be used to restart/start a rook-ceph osd pod without
# osd process running (e.g. when the pod fails to run due to the osd
# failing or the osd needs to be stopped to access the osd data with
# tools like ceph-objectstore-tool).
#
# It patches the deployment, replacing the osd command with
# `sleep infinity`, and executes bash or any other specified command
# inside the pod. On exit it restores the original deployment.
#
# Examples:
#
# Restart the osd.0 pod and execute bash
#
#   ./rook-osd-repair.sh osd.0
#
# Restart the osd.0 pod and execute a ceph-objectstore-tool command:
#
#   ./rook-osd-repair.sh osd.0 ceph-objectstore-tool \
#      --data-path /var/lib/ceph/osd/ceph-0 --op list-pgs
#

#
# Globals
#

NAMESPACE=rook-ceph

#
# Functions
#

usage() {
    echo "usage: $0 <osd-id>" >&2
}

get_osd_pod_name() {
    local id=$1

    kubectl -n rook-ceph get pods | grep "^rook-ceph-osd-${id}-" |
	awk '{print $1}'
}

backup_deployment() {
    local id=$1

    kubectl -n ${NAMESPACE} get deployment rook-ceph-osd-${id} -o yaml \
	    > ${TEMPDIR}/rook-ceph-osd-${id}-deployment.yaml
}

restore_deployment() {
    local id=$1

    kubectl replace --force -f ${TEMPDIR}/rook-ceph-osd-${id}-deployment.yaml
}

patch_deployment() {
    local id=$1
    local i pod host_ip

    kubectl -n ${NAMESPACE} patch deployment rook-ceph-osd-${id} --type='json' \
	    -p '[{"op":"remove", "path":"/spec/template/spec/containers/0/livenessProbe"}]'
    kubectl -n ${NAMESPACE} patch deployment rook-ceph-osd-${id} \
	    -p '{"spec": {"template": {"spec": {"containers": [{"name": "osd", "command": ["sleep", "infinity"], "args": []}]}}}}'

    kubectl -n ${NAMESPACE} wait --for=condition=Progressing deployment/rook-ceph-osd-${id}

    echo -n "waiting for pod " >&2
    for i in `seq 60`; do
	echo -n "." >&2
	kubectl -n rook-ceph exec -it deploy/rook-ceph-osd-${id} -- \
		ps auxww 2>/dev/null | grep -q 'sleep infinity' && break
	sleep 1
    done
    echo >&2

    kubectl -n rook-ceph exec -it deploy/rook-ceph-osd-${id} -- \
	    ps auxww 2>/dev/null | grep -q 'sleep infinity'

    pod=$(get_osd_pod_name ${id})
    test -n "${pod}"

    host_ip=$(kubectl -n rook-ceph get pod ${pod} -o jsonpath='{.status.hostIP}')

    host_path=$(kubectl -n rook-ceph get pod ${pod} -o json |
                jq -r '.spec.volumes[] | select(.name == "rook-ceph-log").hostPath.path')

    echo "${pod} pod started" >&2
    echo "CWD on the host: ${host_ip}:${host_path}" >&2
}

pod_exec() {
    local id=$1
    shift

    kubectl -n ${NAMESPACE} exec -it deploy/rook-ceph-osd-${id} -- "$@"
}

#
# Main
#

case "$1" in
    [0-9]*)
        id=$1
        ;;
    osd.[0-9]*)
        id=${1#osd.}
        ;;
    -h|--help)
        usage
	exit 0
        ;;
    *)
        usage >&2
	exit 1
        ;;
esac

if ! echo $id  | grep -Eq "^[0-9]+$" ; then
    usage >&2
    exit 1
fi

shift

#set -x

TEMPDIR=`mktemp -d`

backup_deployment ${id}
trap "restore_deployment ${id}" INT TERM EXIT

patch_deployment ${id}

if [ -z "$1" ]; then
    set bash
fi

pod_exec ${id} "$@"

#!/bin/sh -ex
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

# For testing
# alias kubectl="echo kubectl"

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
    local i pod

    kubectl -n ${NAMESPACE} patch deployment rook-ceph-osd-${id} --type='json' \
	    -p '[{"op":"remove", "path":"/spec/template/spec/containers/0/livenessProbe"}]'
    kubectl -n ${NAMESPACE} patch deployment rook-ceph-osd-${id} \
	    -p '{"spec": {"template": {"spec": {"containers": [{"name": "osd", "command": ["sleep", "infinity"], "args": []}]}}}}'

    kubectl -n ${NAMESPACE} wait --for=condition=Progressing deployment/rook-ceph-osd-${id}
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

TEMPDIR=`mktemp -d`

backup_deployment ${id}
trap "restore_deployment ${id}" INT TERM EXIT

patch_deployment ${id}

if [ -z "$1" ]; then
    set bash
fi

pod_exec ${id} "$@"

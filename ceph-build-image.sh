#!/bin/sh -ex

# Build a custom Ceph image using an upstream Ceph image as a base and
# adding custom packages from shaman.

BASE_IMAGE="quay.io/ceph/ceph:v17.2.7"
REPO_URL="https://1.chacra.ceph.com/r/ceph/quincy/2fb9be6bf74930dca8fa4d1d9bb7baa633e62446/centos/8/flavors/default/"
TAG="quincy-2fb9be6"
DEST_IMAGE_REPOSITORY=trociny/ceph

TEMPDIR=`mktemp -d`
cleanup() {
	rm -rf $TEMPDIR
}
trap cleanup INT TERM EXIT

cd $TEMPDIR

cat <<EOF > ceph.repo
[Ceph]
name=Ceph packages for \$basearch
baseurl=${REPO_URL}/\$basearch
enabled=1
gpgcheck=0
type=rpm-md

[Ceph-noarch]
name=Ceph noarch packages
baseurl=${REPO_URL}/noarch
enabled=1
gpgcheck=0
type=rpm-md

[ceph-source]
name=Ceph source packages
baseurl=${REPO_URL}/SRPMS
enabled=1
gpgcheck=0
type=rpm-md
EOF

cat <<EOF > Dockerfile
FROM $BASE_IMAGE
COPY ceph.repo /etc/yum.repos.d/ceph.repo
RUN dnf makecache && dnf install -y ceph && dnf clean all
EOF

docker build -t ceph:$TAG .

if [ -n "$DEST_IMAGE_REPOSITORY" ]; then
    docker tag ceph:$TAG ${DEST_IMAGE_REPOSITORY}:$TAG
    docker push ${DEST_IMAGE_REPOSITORY}:${TAG}
fi

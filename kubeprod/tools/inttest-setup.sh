#!/bin/sh

bindir=$GOPATH/bin
PATH=$bindir:$PATH

PLATFORM="$1"

: ${GOOS:-$(go env GOOS)}
: ${GOARCH:-$(go env GOARCH)}

set -e -x

set -- $(echo $PLATFORM | sed 's/^\(.*)-\(.*\)+k8s-\(.*\)$/\1 \2 \3/')
platform=$1
platvers=$2
k8svers=$3

if ! which kubectl; then
    wget -O $bindir/kubectl https://storage.googleapis.com/kubernetes-release/release/$k8svers/bin/$GOOS/$GOARCH/kubectl
    chmod +x $bindir/kubectl
fi

case $platform in
    minikube)
        minikubevers=$platvers.0
        minikube=minikube-$minikubevers
        if ! which $minikube; then
            wget -O $bindir/$minikube https://storage.googleapis.com/minikube/releases/v$minikubevers/minikube-$GOOS-$GOARCH
            chmod +x $bindir/$minikube
        fi

        MINIKUBE_WANTUPDATENOTIFICATION=false
        MINIKUBE_WANTREPORTERRORPROMPT=false
        MINIKUBE_HOME=${HOME}
        CHANGE_MINIKUBE_NONE_USER=true
        export MINIKUBE_WANTUPDATENOTIFICATION
        export MINIKUBE_WANTREPORTERRORPROMPT
        export MINIKUBE_HOME CHANGE_MINIKUBE_NONE_USER

        sudo -E $bindir/$minikube start --vm-driver=none \
             --extra-config apiserver.Authorization.Mode=RBAC \
             --kubernetes-version $k8svers

        $minikube update-context
        $minikube status
        ;;

    *)
        echo "Unknown platform $PLATFORM" >&2
        exit 1
        ;;
esac

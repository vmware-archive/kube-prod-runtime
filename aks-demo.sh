#!/bin/sh
#
# To use (warning: engage brain, don't just cut+paste):
#
# Setup:
#   <git clone repo somewhere>
#   <ensure azure-cli is installed and setup appropriately: az login>
#   <setup glue records for azure-controlled DNS zone used in demo.
#    NS: ns1-09.azure-dns.com. ns2-09.azure-dns.net.
#        ns3-09.azure-dns.org. ns4-09.azure-dns.info. >
#   <optional: set KUBECONFIG to some empty file>
#   make -C kubeprod
#   alias kubeprod=$repo/aks-demo.sh
# Demo:
#   az aks create --resource-group prod-runtime-rg --name demo --node-count 3 --node-vm-size Standard_DS2_v2 --generate-ssh-key --kubernetes-version 1.9.4
#   az aks get-credentials --resource-group prod-runtime-rg --name demo --admin --file $KUBECONFIG
#   kubeprod install --platform aks+k8s-1.9 --email gus@bitnami.com --azure-resource-group prod-runtime-rg --dns-suffix aztest.oldmacdonald.farm
#   helm install stable/wordpress --set ... (<- TODO)

mydir=${0%/*}
# This can go away once we are a public github project
kpargs="--manifests $mydir/manifests"
isinstall=

set -e

while [ $# -gt 0 ] ; do
    case "$1" in
        --azure-resource-group)
            AZURE_RESOURCE_GROUP="$2"
            shift 2
            ;;
        --dns-suffix)
            AZURE_PUBLIC_DNS_ZONE="$2"
            kpargs="--dns-suffix $2"
            shift 2
            ;;
        help|--help)
            kpargs="$kpargs $1"
            isinstall=false
            shift
            ;;
        install)
            kpargs="$kpargs $1"
            : ${isinstall:=true}
            shift
            ;;
        *)
            kpargs="$kpargs $1"
            shift
            ;;
    esac
done

export AZURE_RESOURCE_GROUP AZURE_PUBLIC_DNS_ZONE

$mydir/kubeprod/bin/kubeprod $kpargs

if ${isinstall:-false}; then
    # this is the bit that will/should be rolled into kubeprod more
    # seamlessly than this script.
    echo "---"
    date
    $mydir/kubeprod/hacks/aks-postinst.sh
fi >>aks-postinst.log

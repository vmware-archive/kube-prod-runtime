#!/bin/sh
#
# To use (warning: engage brain, don't just cut+paste):
#
# Setup:
#   <git clone repo somewhere>
#   <ensure azure-cli is installed and setup appropriately: az login>
#   <setup glue records for azure-controlled DNS zone used in demo.
#    See az network dns zone details for nameservers.>
#   <optional: set KUBECONFIG to some empty file>
#   make -C kubeprod
#   alias kubeprod=$repo/aks-demo.sh
#   cat <<EOF >wordpress-values.yaml
#   serviceType: ClusterIP
#   ingress:
#     enabled: true
#     hosts:
#       - name: wordpress.aztest.oldmacdonald.farm
#         tls: true
#         tlsSecret: wordpress-tls
#         annotations:
#           kubernetes.io/tls-acme: true
#   EOF
# Demo:
#   az aks create --resource-group prod-runtime-rg --name demo --node-count 3 --node-vm-size Standard_DS2_v2 --generate-ssh-key --kubernetes-version 1.9.4
#   (creating an AKS cluster typically takes ~15minutes, so don't do that live)
#   az aks get-credentials --resource-group prod-runtime-rg --name demo --admin --file $KUBECONFIG
#   kubeprod install --platform aks+k8s-1.9 --email gus@bitnami.com --azure-resource-group prod-runtime-rg --dns-suffix aztest.oldmacdonald.farm
#   helm init
#   helm install stable/wordpress --values wordpress-values.yaml
#   (wait a few minutes, because nami and letsencrypt/DNS propagation - nami is slower fwiw)
#   <log in using https URL and user/pass instruction on helm output>
#   <Note DNS entry exists/works.  Note TLS certificate exists/works.>
#   Visit https://prometheus.aztest.oldmacdonald.farm/
#   <Note Azure oauth2 authentication>
#   Example query: rate(nginx_requests_total{server_zone="wordpress.aztest.oldmacdonald.farm"}[5m])
#   Visit https://kibana.aztest.oldmacdonald.farm/
#   See eg: wordpress HTTP request logs
#   <Note automatic container log collection>
#

mydir=${0%/*}
# This can go away once we are a public github project
kpargs=""
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
            kpargs="$kpargs --dns-suffix $2"
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
            kpargs="$kpargs --manifests $mydir/manifests"
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

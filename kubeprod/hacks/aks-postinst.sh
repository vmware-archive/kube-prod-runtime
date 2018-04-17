#!/bin/sh
#
# TODO: Rewrite in golang and merge into installer
#
# NOTE! Assumes current az account/subscription is correct!
# NOTE! Assumes current kubectl config/context is correct!
#

set -e -x

: ${AZURE_RESOURCE_GROUP:?AZURE_RESOURCE_GROUP needs to be set}
: ${AZURE_PUBLIC_DNS_ZONE:?AZURE_PUBLIC_DNS_ZONE needs to be set}

az network dns zone create -g $AZURE_RESOURCE_GROUP -n $AZURE_PUBLIC_DNS_ZONE
rgid=$(az group show --name $AZURE_RESOURCE_GROUP --query id -o tsv)

tmpfile=$(mktemp)
trap "rm $tmpfile" EXIT

az ad sp create-for-rbac --role=Contributor --scopes=$rgid --sdk-auth |
    jq --arg rg $AZURE_RESOURCE_GROUP '{"tenantId": .tenantId, "subscriptionId": .subscriptionId, "aadClientId": .clientId, "aadClientSecret": .clientSecret, "resourceGroup": $rg}' |
    tee $tmpfile

kubectl delete secret --ignore-not-found -n kube-system external-dns-azure-config
kubectl create secret generic --from-file=azure.json=$tmpfile -n kube-system external-dns-azure-config

# TODO: Configure dns01 provider after cert-manager 0.3 is released

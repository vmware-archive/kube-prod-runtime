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

authfile=$(mktemp)
trap "rm $authfile" EXIT

az ad sp create-for-rbac \
   --role=Contributor \
   --scopes=$rgid \
   --sdk-auth \
    | \
    jq --arg rg $AZURE_RESOURCE_GROUP '{"tenantId": .tenantId, "subscriptionId": .subscriptionId, "aadClientId": .clientId, "aadClientSecret": .clientSecret, "resourceGroup": $rg}' |
    tee $authfile

kubectl delete secret \
        --ignore-not-found \
        -n kube-system external-dns-azure-config
kubectl create secret generic \
        --from-file=azure.json=$authfile \
        -n kube-system external-dns-azure-config

# TODO: Configure dns01 provider after cert-manager 0.3 is released

# ---

oauth_host=oauth.$AZURE_PUBLIC_DNS_ZONE

oauthfile=$(mktemp)
trap "rm $oauthfile" EXIT

client_secret=$(python -c 'import os,base64; print base64.b64encode(os.urandom(18))')
# I Quote: cookie_secret must be 16, 24, or 32 bytes to create an AES cipher when pass_access_token == true or cookie_refresh != 0
cookie_secret=$(python -c 'import os,base64; print base64.b64encode(os.urandom(24))')

# "User.Read" for "Microsoft.Azure.ActiveDirectory"
# aka "Sign in and read user profile"
manifest='
[{
  "resourceAppId": "00000002-0000-0000-c000-000000000000",
  "resourceAccess": [
    {
      "id": "311a71cc-e848-46a1-bdf8-97ff7156d8e6",
      "type": "Scope"
    }
  ]
}]
'

reply_urls() {
    for h in prometheus kibana; do
        echo "https://$h.$AZURE_PUBLIC_DNS_ZONE/oauth2/callback"
    done
}

createupdate() {
    id="$1"; shift
    if az ad app show --id $id --query none; then
        az ad app update --id $id "$@"
        az ad app show --id $id
    else
        az ad app create "$@"
    fi
}

createupdate \
    https://$oauth_host/oauth2 \
    --display-name 'Kubeprod cluster management' \
    --password "$client_secret" \
    --identifier-uris https://$oauth_host/oauth2 \
    --reply-urls $(reply_urls) \
    --required-resource-accesses "$manifest" \
    >$oauthfile
cat $oauthfile
# --homepage ?

kubectl delete secret \
        --ignore-not-found \
        -n kube-system oauth2-proxy
kubectl create secret generic \
        --from-literal=client_id=$(jq -r <$oauthfile .appId) \
        --from-literal=client_secret=$client_secret \
        --from-literal=cookie_secret=$cookie_secret \
        --from-literal=azure_tenant=$(jq -r <$authfile .tenantId) \
        -n kube-system oauth2-proxy

# TODO: should reread secret configs somehow (eg: use configmap-reload)
kubectl delete pod -n kube-system -l name=oauth2-proxy

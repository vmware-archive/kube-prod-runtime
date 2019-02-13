FROM alpine:3.8

LABEL maintainer "Bitnami <containers@bitnami.com>"

ARG BKPR_VERSION

RUN : "${BKPR_VERSION:?BKPR_VERSION build argument not specified}"

RUN apk add --update ca-certificates \
 && mkdir -p "/usr/lib/bkpr/" \
 && wget "https://github.com/bitnami/kube-prod-runtime/releases/download/${BKPR_VERSION}/bkpr-${BKPR_VERSION}-linux-amd64.tar.gz" \
 && tar -zxf "bkpr-${BKPR_VERSION}-linux-amd64.tar.gz" -C "/usr/bin/" "bkpr-${BKPR_VERSION}/kubeprod" --strip 1 \
 && tar -zxf "bkpr-${BKPR_VERSION}-linux-amd64.tar.gz" -C "/usr/lib/bkpr/" "bkpr-${BKPR_VERSION}/manifests" --strip 1 \
 && chmod +x "/usr/bin/kubeprod" \
 && rm -rf "bkpr-${BKPR_VERSION}-linux-amd64.tar.gz" \
 && rm /var/cache/apk/*

WORKDIR /bkpr

ENTRYPOINT ["kubeprod"]

CMD ["help"]

#!/usr/bin/env bash

set -o errexit
set -o nounset

exec /opt/jboss/tools/docker-entrypoint.sh -b 0.0.0.0 -Dkeycloak.import=/realm/bkpr-realm.json -c standalone.xml

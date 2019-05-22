#!/bin/bash

# Set shell options
set -e

# Set retention days
RETENTION_DAYS="90"

#
if [ "$(uname -s)" == 'Darwin' ]; then
    if command -v gdate; then
        date="gdate"
    fi
elif [ "$(uname -s)" == 'Linux' ]; then
    date="date"
fi

# Create a list of 365 indices
LIST_INDICES=$(for i in $(seq 0 364); do ${date} -d "-$i day" +%Y.%m.%d; done | sort)

# We should have 365 indices
TOTAL_INDICES=$(echo "${LIST_INDICES}" | wc -w | tr -d ' ')

# Create a temporary file for dumping stuff there
tempfile="/tmp/$RANDOM$RANDOM"

# Test if the 9200 port is in use. Do not fail!!
nc -zv localhost 9200 2>"${tempfile}" || true
in_use=$(
    grep -q 'succeeded!' "${tempfile}"
    echo $?
)

# Check if the port 9200 it's in use (something goes wrong if yes ATM)
if [ "${in_use}" -ne '0' ]; then
    svc=$(kubectl get svc -n kubeprod elasticsearch-logging -o NAME)
    port-fwd=$(kubectl -n kubeprod port-forward "${svc}" 9200) &
else
    echo "port 9200 already in use. Quitting..."
    exit 12
fi

# Create the curator cronjob
# Overwrite the tempfile
jsonnet --ext-str "retention_days=${RETENTION_DAYS}" \
    --ext-str "host=http://elasticsearch-logging.kubeprod.svc.cluster.local" \
    --ext-str "port=9200" --ext-str "schedule=*/2 * * * *" \
    -e '(import "../../manifests/components/elasticsearch-curator.jsonnet") + {
          items_+: {
    	    retention_days: std.parseInt(std.extVar("retention_days")),
    	    elasticsearch_host: std.extVar("host"),
    	    elasticsearch_curator_schedule: std.extVar("schedule"),
    	    elasticsearch_port: std.parseInt(std.extVar("port")),
                },
          }' >"${tempfile}"

# Delete default cronjob to create ours later. Allow failure
kubectl delete -f "${tempfile}" || true

# Let the port-fwd to stablish the connection
sleep 15

# Create  365 indices, one per day of the year, 10 in parallel
echo "${LIST_INDICES}" | xargs -n1 -P10 -I@ curl -s -X PUT \
    http://localhost:9200/logstash-@ >/dev/null 2>&1

# Sleep for 5 minutes for let indices go green
sleep 300

# Deploy to k8s
kubectl replace --force --validate=true -f "${tempfile}"

# Sleep for two minutes to let the cronjob be executed
sleep 120

# Check how many indices are on ES
NOW_INDICES=$(curl -s http://localhost:9200/_cat/indices | grep -cE "green(.*)open(.*)logstash" | tr -d ' ')

# Check how many indices exists.
# We should have "${RETENTION_DAYS}" indices
if [ "${TOTAL_INDICES}" == '365' ] && [ "${NOW_INDICES}" == "${RETENTION_DAYS}" ]; then
    echo "Cleaned up indices successfully"
    exit 0
else
    echo "FAILURE: unexpected number of indices"
    exit 14
fi

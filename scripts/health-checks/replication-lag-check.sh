#!/usr/bin/env bash
# Compares live replication lag with the thresholds in docs/03-data-replication/replication-strategy.md Section 10.
# Read-only. Exit 0 if every component is inside its threshold, 1 otherwise.
# Usage: ./replication-lag-check.sh
set -euo pipefail
# shellcheck source=../common.sh
source "$(dirname "$0")/../common.sh"
require_cmd aws

START="$(date -u -d '-5 minutes' +%Y-%m-%dT%H:%M:%SZ)"
END="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# max_metric REGION NAMESPACE METRIC DIMENSIONS... -> prints the maximum over the last 5 minutes, or "none"
max_metric() {
  local region="$1" ns="$2" metric="$3"; shift 3
  local v
  v="$(aws cloudwatch get-metric-statistics --region "$region" --namespace "$ns" --metric-name "$metric" \
        --dimensions "$@" --start-time "$START" --end-time "$END" --period 60 --statistics Maximum \
        --query 'max(Datapoints[].Maximum)' --output text 2>/dev/null || echo None)"
  case "$v" in None|"") echo none ;; *) echo "$v" ;; esac
}

check() {
  local label="$1" value="$2" threshold="$3" unit="$4"
  if [ "$value" = "none" ]; then
    warn "$label: no data in the last 5 minutes (alarm treats missing data as breaching)"
  elif awk -v a="$value" -v b="$threshold" 'BEGIN{exit !(a<=b)}'; then
    pass "$label: ${value} ${unit} (limit ${threshold})"
  else
    fail "$label: ${value} ${unit} exceeds ${threshold}"
  fi
}

log "Replication lag check (window ${START} to ${END})"

check "Aurora global DB lag" \
  "$(max_metric "$DR_REGION" AWS/RDS AuroraGlobalDBReplicationLag Name=DBClusterIdentifier,Value=paysecure-secondary)" 500 ms

for t in paysecure-idempotency paysecure-sessions; do
  check "DynamoDB ${t} replication latency" \
    "$(max_metric "$PRIMARY_REGION" AWS/DynamoDB ReplicationLatency "Name=TableName,Value=${t}" "Name=ReceivingRegion,Value=${DR_REGION}")" 1000 ms
done

check "MSK Replicator message lag" \
  "$(max_metric "$DR_REGION" AWS/Kafka MessageLag "Name=Replicator Name,Value=paysecure-replicator")" 10000 messages

warn "ElastiCache Global Datastore lag (2,000 ms limit) is not checked here: confirm the CloudWatch metric name for your engine version, then add it"
warn "S3 CRR: check the OperationsFailedReplication alarm state in the console or the Prometheus rule S3ReplicationFailed"

summary_and_exit

#!/usr/bin/env bash
# Data sovereignty check: proves no resources exist outside ap-south-1 and ap-south-2
# (docs/07-data-sovereignty/compliance-matrix.md Section 8) and that replication targets are Indian buckets.
# Read-only. Exit 0 = clean. Attach the output to the drill report.
# Usage: AGGREGATOR=paysecure-org ./sovereignty-check.sh
# Optional: TEXTFILE_DIR=/var/lib/node_exporter/textfile writes metrics for the Prometheus alerts.
set -euo pipefail
# shellcheck source=../common.sh
source "$(dirname "$0")/../common.sh"
require_cmd aws jq

AGGREGATOR="${AGGREGATOR:-paysecure-org}"
ALLOWED='ap-south-1 ap-south-2'

log "Sovereignty check using Config aggregator ${AGGREGATOR}"

# 1. Resources outside the two Indian regions. Global services (IAM, Route 53, CloudFront) report region 'global'.
QUERY="SELECT resourceId, resourceType, awsRegion WHERE awsRegion NOT IN ('ap-south-1','ap-south-2','global')"
OUT="$(aws configservice select-aggregate-resource-config --configuration-aggregator-name "$AGGREGATOR" \
        --expression "$QUERY" --region "$PRIMARY_REGION" --output json)"
COUNT="$(jq '.Results | length' <<<"$OUT")"

if [ "$COUNT" -eq 0 ]; then
  pass "No Config-tracked resources outside ${ALLOWED}"
else
  fail "${COUNT} resource(s) outside the Indian regions:"
  jq -r '.Results[] | fromjson | "    \(.awsRegion)  \(.resourceType)  \(.resourceId)"' <<<"$OUT"
fi

# 2. Replication destinations of every source bucket must be in an Indian region.
for b in $(aws s3api list-buckets --region "$PRIMARY_REGION" --query "Buckets[?starts_with(Name, 'paysecure-')].Name" --output text); do
  cfg="$(aws s3api get-bucket-replication --bucket "$b" --region "$PRIMARY_REGION" --output json 2>/dev/null || true)"
  [ -n "$cfg" ] || continue
  for dest in $(jq -r '.ReplicationConfiguration.Rules[].Destination.Bucket' <<<"$cfg"); do
    name="${dest##*:}"
    region="$(aws s3api get-bucket-location --bucket "$name" --query LocationConstraint --output text 2>/dev/null || echo unknown)"
    case " ${ALLOWED} " in
      *" ${region} "*) pass "Replication ${b} -> ${name} (${region})" ;;
      *) fail "Replication ${b} -> ${name} is in '${region}', outside India" ;;
    esac
  done
done

write_metric paysecure_resources_outside_india_count "$COUNT"
write_metric paysecure_sovereignty_check_timestamp_seconds "$(date +%s)"
summary_and_exit

#!/usr/bin/env bash
# Returns the platform to normal after a drill: un-invert the Mumbai health check, DNS TTL back to 30 s,
# and print the replication direction for the operator to confirm. Dry run by default.
# For a failback of the DATA direction (Aurora, Redis) use the RB-01 failback steps; this script does not move databases.
# Usage: HC_MUM_ID=... ZONE_ID=... ./restore-normal.sh [--execute]
set -euo pipefail
HERE="$(dirname "$0")"
# shellcheck source=../common.sh
source "$HERE/../common.sh"
require_cmd aws
: "${HC_MUM_ID:?set HC_MUM_ID}" "${ZONE_ID:?set ZONE_ID}"
[ "${1:-}" = "--execute" ] && EXECUTE=1
confirm RESTORE

run aws route53 update-health-check --health-check-id "$HC_MUM_ID" --no-inverted
if [ "$EXECUTE" = "1" ]; then "$HERE/set-dns-ttl.sh" 30 --execute; else "$HERE/set-dns-ttl.sh" 30; fi

log "Current Aurora global cluster members (confirm the writer is where you intend):"
aws rds describe-global-clusters --region "$DR_REGION" --global-cluster-identifier "$GLOBAL_CLUSTER" \
  --query 'GlobalClusters[0].GlobalClusterMembers[*].[DBClusterArn,IsWriter]' --output table
log "Next: run post-drill-reconcile.sh, then complete the drill report."

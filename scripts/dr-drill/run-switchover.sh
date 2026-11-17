#!/usr/bin/env bash
# Drill #1 (planned switchover, annual-drill-plan.md Section 5.1): runs pre-drill checks, then the planned
# Mumbai -> Hyderabad switchover. Dry run by default; --execute for the real thing (typed confirmation).
# Usage: HC_MUM_ID=... HC_HYD_ID=... KAFKA_BOOTSTRAP_DR=... ZONE_ID=... ./run-switchover.sh [--execute]
set -euo pipefail
HERE="$(dirname "$0")"
# shellcheck source=../common.sh
source "$HERE/../common.sh"
: "${HC_HYD_ID:?set HC_HYD_ID}"

log "Drill #1: planned switchover"
"$HERE/pre-drill-checks.sh" || die "Pre-drill checks failed: NO-GO"
exec "$HERE/../failover/failover-to-hyderabad.sh" --mode planned "$@"

#!/usr/bin/env bash
# Shared helpers for PaySecure DR scripts. Source this file; do not execute it.
# Safe by default: anything that changes infrastructure goes through `run`, which only prints
# the command unless EXECUTE=1 (set by --execute in the calling script).

PRIMARY_REGION="${PRIMARY_REGION:-ap-south-1}"
DR_REGION="${DR_REGION:-ap-south-2}"
# shellcheck disable=SC2034
GLOBAL_CLUSTER="paysecure-global"
EXECUTE="${EXECUTE:-0}"
PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0

if [ -t 1 ]; then
  RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; RESET=$'\033[0m'
else
  RED=""; GREEN=""; YELLOW=""; RESET=""
fi

ts()   { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
log()  { printf '[%s] %s\n' "$(ts)" "$*"; }
die()  { printf '%s[%s] ERROR: %s%s\n' "$RED" "$(ts)" "$*" "$RESET" >&2; exit 1; }
pass() { PASS_COUNT=$((PASS_COUNT + 1)); printf '  %sPASS%s  %s\n' "$GREEN" "$RESET" "$*"; }
fail() { FAIL_COUNT=$((FAIL_COUNT + 1)); printf '  %sFAIL%s  %s\n' "$RED" "$RESET" "$*"; }
warn() { WARN_COUNT=$((WARN_COUNT + 1)); printf '  %sWARN%s  %s\n' "$YELLOW" "$RESET" "$*"; }

require_cmd() {
  local c
  for c in "$@"; do
    command -v "$c" >/dev/null 2>&1 || die "required command not found: $c"
  done
}

# Run a state-changing command, or print it when not executing.
run() {
  if [ "$EXECUTE" = "1" ]; then
    log "RUN: $*"
    "$@"
  else
    log "[dry-run] $*"
  fi
}

# Typed confirmation before any production change.
confirm() {
  local word="$1"
  [ "$EXECUTE" = "1" ] || return 0
  printf 'Type %s to continue: ' "$word"
  local answer
  read -r answer
  [ "$answer" = "$word" ] || die "confirmation not given, aborting"
}

account_id() { aws sts get-caller-identity --query Account --output text; }

# Write a Prometheus textfile-collector metric (picked up by node-exporter).
write_metric() {
  local name="$1" value="$2" labels="${3:-}" dir="${TEXTFILE_DIR:-}"
  [ -n "$dir" ] || return 0
  mkdir -p "$dir"
  printf '%s%s %s\n' "$name" "$labels" "$value" >> "$dir/paysecure_dr.prom.tmp"
  mv "$dir/paysecure_dr.prom.tmp" "$dir/paysecure_dr.prom"
}

summary_and_exit() {
  echo
  log "Result: ${PASS_COUNT} passed, ${FAIL_COUNT} failed, ${WARN_COUNT} warnings"
  [ "$FAIL_COUNT" -eq 0 ]
}

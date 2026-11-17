# Monitoring configs

| File | Purpose |
|---|---|
| `dr-alerts.rules.yml` | Prometheus rules: replication lag (thresholds from `replication-strategy.md` Section 10), DR composite, payment success and latency, sovereignty check, last drill RTO |
| `alertmanager-routes.yml` | Routing: P1/P2 to PagerDuty with minimal payloads, drills never page real escalation policies |
| `grafana-dr-readiness-dashboard.json` | The "DR readiness" dashboard that shows last drill RTO (see `dns-failover-design.md`) |

**Status:** YAML and JSON parse correctly; not loaded into a running Prometheus, Alertmanager or Grafana. Metric names are assumptions (CloudWatch exporter naming): run `promtool check rules dr-alerts.rules.yml` and adjust names to match your exporters. The ElastiCache Global Datastore lag metric in particular must be confirmed.

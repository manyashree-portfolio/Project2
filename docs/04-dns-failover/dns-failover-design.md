# DNS Failover and Health Check Specification

Companion files: `health-check-config.yaml`, `route53-config.json`, `failover-timing-diagram.md`. All values are consistent with the active-passive design (Mumbai primary, Hyderabad hot standby).

## 1. Goals and Constraints
- Redirect `api.paysecure.in` traffic from Mumbai to Hyderabad automatically when Mumbai is lost, inside the 5-minute RTO.
- Avoid false-positive failovers (an unnecessary failover is itself an outage risk and a regulatory event).
- Never route customer traffic to a region that cannot process payments correctly.
- Detection and routing must not depend on infrastructure in the failed region.

## 2. Routing Policy
Route 53 **failover routing** with two records for `api.paysecure.in`:
| Record | Set identifier | Role | Target | Health check | TTL |
|---|---|---|---|---|---|
| CNAME | mumbai-primary | PRIMARY | Mumbai ALB DNS name | `mum-region-calculated` | 30 s |
| CNAME | hyderabad-secondary | SECONDARY | Hyderabad ALB DNS name | `hyd-api-live-health` | 30 s |

**Why CNAME and not alias.** Alias records pointing at an ALB are free of query charges but inherit the load balancer's fixed 60-second TTL, which cannot be lowered. A 30-second TTL on a CNAME reduces the worst-case client cache time by 30 seconds, at a small extra query cost. Alias records also allow "Evaluate Target Health", which is not needed because explicit health checks are attached.

Per-region helper names `api-mum.paysecure.in` and `api-hyd.paysecure.in` (60 s TTL, not under failover) let health checkers, partner banks and the operations team address a specific region directly, which is also the emergency access path if DNS itself is the problem (RB-03).

## 3. Health Check Design
Route 53 checkers run outside India, so the ALB health endpoints are public, protected by WAF rules that allow the Route 53 health checker IP ranges.

**Three signals per region, combined into one calculated health check.**
| Child check | What it proves | Parameters |
|---|---|---|
| `mum-api-deep-health` | API, Aurora writer, DynamoDB, Redis and Kafka are reachable from the app | HTTPS 443, `/health/deep`, interval 10 s, failure threshold 3 |
| `mum-synthetic-transaction` | A complete test payment succeeded in the last 60 s | HTTPS 443, `/health/synthetic`, interval 10 s, failure threshold 3 |
| `mum-api-success-rate-alarm` | Real traffic is succeeding | CloudWatch alarm: payment API success rate (2xx/total) below 99.5% for 2 minutes |

**Calculated health check `mum-region-calculated`:** healthy while at least 2 of the 3 children are healthy. A single failing signal (for example a slow deep-health query) does not trigger failover, which removes the main source of false positives. The calculated check is unhealthy when 2 or more signals fail.

**Standby check `hyd-api-live-health`:** a simple HTTPS check on `/health/live` confirming that the Hyderabad stack is up. It deliberately does *not* require Hyderabad to be write-ready. Route 53 failover routing returns the primary record if *both* records are unhealthy, so a standby check that failed before promotion would stop Route 53 from ever switching. Write-readiness is enforced in the application instead (Section 5).

**Detection time.** Interval 10 s x failure threshold 3 = **30 seconds minimum** (interval 30 s would give 90 s). Using the 10-second "fast" interval costs about $1 per health check per month extra, which is negligible compared with 60 seconds of saved downtime.

## 4. Failover Decision Logic
The Route 53 flip is automatic and immediate once the calculated check is unhealthy. Database promotion is controlled by a **failover controller** (Step Functions + Lambda running in Hyderabad) triggered by the same health state.

Automatic promotion happens only when **all** of these hold (see the YAML):
1. The Mumbai calculated check has been unhealthy for 30 seconds.
2. An independent probe in Singapore also cannot reach Mumbai (rules out a Route 53 checker problem or a partition between Hyderabad and Mumbai).
3. The last known Aurora global replication lag was within the 60-second RPO.
4. The Hyderabad composite readiness check is healthy.
5. No failover has taken place in the last 30 minutes (anti-flapping).

The Incident Commander has a **15-second veto window**. If any condition is not met, for example a suspected network partition where Mumbai still responds to some probes, the controller pages the Incident Commander and waits for a manual decision (RB-05). Failback is always manual and scheduled.

**Fencing before promotion.** Withdraw the primary DNS record, close the Mumbai writer security group, and disable CI/CD deploys. This prevents a partially-alive Mumbai from accepting writes and creating a second writer.

## 5. Write-Ready Gate
Because DNS flips at about T+30 s and promotion finishes at about T+2:45, Hyderabad's payment-api returns **HTTP 503 with `Retry-After: 5`** for write operations until the gate opens. The gate opens when Aurora reports the writer role, ElastiCache is primary, Kafka consumers are assigned and a synthetic write succeeds. Read-only status endpoints may return data from the replica with a header `X-Data-Freshness: replica`. Merchants' retries are safe because every request has an idempotency key.

## 6. TTL Strategy
| TTL | Failover impact | Query cost and load | Use here |
|---|---|---|---|
| 10 s | Clients switch within about 10 s | Highest; resolvers hit Route 53 6x as often as at 60 s | Set temporarily 24 hours before drills |
| **30 s** | **Clients switch within about 30 s** | **Moderate** | **Normal operation (chosen)** |
| 60 s | Within about 60 s | Standard | Helper names; alias default |
| 300 s | Up to 5 minutes | Lowest | Rejected: would consume the whole RTO |

Cost check: 45,000 merchants plus consumer clients produce a manageable query volume, and Route 53 query pricing is small compared with the infrastructure budget. A 30-second TTL is therefore a 30-second-faster RTO for a negligible fee.

**Caveat.** Some resolvers and client libraries (JVM DNS caching, long-lived connection pools) ignore TTLs. Mitigations: set the JVM `networkaddress.cache.ttl` to 30, use short connection lifetimes (60 s) in merchant SDKs, and publish a client integration guide asking merchants to honour DNS TTLs and retry with the same idempotency key.

## 7. Real-World RTO (response to BCRB Challenge 2)
The CTO's challenge assumed detection, failover and DNS propagation add up sequentially (30 + 90 + 60 = 180 s plus in-flight effects). In this design DNS propagation overlaps with promotion:

| Scenario | First successful write | Notes |
|---|---|---|
| Best case | about 2 min 15 s | Aurora promotion at 60 s, no stragglers |
| **Nominal** | **about 2 min 45 s** | Longest parallel step (EKS scale-out 120 s) after 45 s detection and decision |
| Pessimistic (P95) | about 4 min | +30 s connection-pool re-establishment, +45 s retry-storm recovery |
| Tail clients | 5 min or more | Resolvers that ignore TTLs: up to 60 s extra for a small share of clients |

**Documented RTO: 4 minutes** (P95), nominal 2:45, with the long tail acknowledged. The quarterly drills measure the actual figure, and the success criterion is P95 under 5 minutes. If a drill exceeds 5 minutes, the RTO risk is escalated to the BCRB and the active-active upgrade triggers are reviewed.

**Retry storms.** On failover, merchants retry. Mitigations are the rate limiter (pre-warmed in Hyderabad), `Retry-After` headers, exponential backoff with jitter in the service mesh, and Shield Advanced / WAF rate-based rules.

## 8. Security of the DNS Layer
- DNSSEC signing enabled for the hosted zone; the KMS key for signing is in us-east-1 as required by Route 53 (no payment data involved).
- Route 53 changes restricted by IAM to the failover controller role and a break-glass role with MFA; every change is logged in CloudTrail with an alarm on unexpected `ChangeResourceRecordSets`.
- Registrar lock and a secondary authoritative DNS provider plan for a Route 53 service failure (RB-03 documents the switch and the direct-IP fallback for critical partner banks).

## 9. Monitoring and Alerts
- Route 53 health check status for each checker (P1 on any failure).
- `HealthCheckPercentageHealthy` and `ChildHealthCheckHealthyCount` for the calculated check.
- CloudWatch alarm for unexpected DNS record changes.
- Synthetic DNS verification every 60 seconds from outside AWS, confirming that `api.paysecure.in` resolves to the expected region (detects poisoning or misconfiguration).
- DR readiness dashboard panel: estimated failover time and last drill RTO.

## 10. Testing
- **Monthly (Month 4 component drill):** switch Route 53 with a manual health check status override and measure client switch time.
- **Quarterly:** full-failover drills measuring time to first successful write, with results recorded in the drill-success template.
- **Before each drill:** lower the TTL to 10 s 24 hours earlier, then restore to 30 s.

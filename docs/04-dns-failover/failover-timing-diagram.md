# Failover Timing Diagram

Time zero is the moment Mumbai (ap-south-1) fails. DNS redirection and data-store promotion run in parallel, and Hyderabad returns HTTP 503 with `Retry-After` for writes until the write-ready gate opens.

## 1. Timeline (nominal)
```mermaid
gantt
    title Regional failover timeline (mm:ss)
    dateFormat mm:ss
    axisFormat %M:%S
    section Detection
    Health checks fail 3 x 10 s              :det, 00:00, 30s
    section Decision
    Independent probe, lag check, fencing    :dec, 00:30, 15s
    section DNS
    Route 53 flips to Hyderabad              :dns1, 00:30, 5s
    Clients re-resolve (TTL 30 s)            :dns2, 00:35, 40s
    section Promotion (parallel)
    Aurora global failover                   :aur, 00:45, 90s
    ElastiCache promotion                    :red, 00:45, 60s
    Kafka consumers switch                   :msk, 00:45, 30s
    EKS scale-out 12 to 24 nodes             :eks, 00:45, 120s
    section Recovery
    Write-ready gate opens (first write)     :milestone, ready, 02:45, 0s
    Verification and traffic check           :ver, 02:45, 40s
    RTO target 4:00                          :milestone, tgt, 04:00, 0s
    Mandate limit 5:00                       :crit, milestone, lim, 05:00, 0s
```

## 2. Timing Table
| Phase | Start | Duration | End | Basis |
|---|---|---|---|---|
| Detection (3 failed checks at 10 s) | 0:00 | 30 s | 0:30 | Route 53 health check configuration |
| Decision, independent probe, fencing | 0:30 | 15 s | 0:45 | Controller logic, includes 15 s veto window |
| Route 53 record flip | 0:30 | 5 s | 0:35 | Route 53 changes propagate to authoritative servers in seconds |
| Client DNS re-resolution | 0:35 | up to 30 s | up to 1:05 (overlaps promotion) | TTL 30 s |
| Aurora global failover to Hyderabad | 0:45 | 60-90 s | up to 2:15 | Managed failover, typically 1-2 minutes |
| ElastiCache promotion | 0:45 | 30-60 s | up to 1:45 | Global Datastore failover |
| Kafka consumers switch and resume | 0:45 | 30 s | 1:15 | Offsets already replicated |
| EKS scale-out (pre-warmed 12 to 24 nodes) | 0:45 | 90-120 s | up to 2:45 | **Critical path** |
| Write-ready gate opens | 2:45 | 5 s | 2:50 | Synthetic write passes |
| Verification | 2:45 | 40 s | 3:25 | Synthetic transactions, error rate, queue drain |

**Critical path:** detection (30 s) + decision (15 s) + EKS scale-out (120 s) = 2 min 45 s to first successful write. Documented RTO target is 4 minutes, leaving 1 min 15 s of buffer, and the mandate is 5 minutes.

## 3. Sensitivity Analysis
| Change | Effect on first successful write |
|---|---|
| TTL 60 s instead of 30 s | No change for the first write on the critical path, but clients that cached the old record stay on Mumbai up to 30 s longer (tail latency) |
| Health check interval 30 s instead of 10 s | +60 s (detection 90 s) so first write at about 3 min 45 s |
| No pre-warmed compute (cold EKS scale-out about 6-8 minutes) | RTO becomes about 7-9 minutes, **fails the mandate**, which is why 50% compute is pre-provisioned |
| Decision by manual approval (assume 3 minutes) | +about 2 min 15 s over the automated 15 s path, so manual approval is limited to ambiguous cases |
| Aurora replication lag above 60 s at failure | Controller pauses and asks the Incident Commander (data-loss decision) |

## 4. Real-World Adjustments
Added to the nominal critical path for the pessimistic (P95) case:
| Effect | Added time |
|---|---|
| Connection pools reconnecting to the new Aurora writer | +30 s |
| Merchant retry storm until backoff settles | +45 s |
| **P95 first successful write** | **about 4 min** |
| Resolvers that ignore TTL (small share of clients) | up to +60 s |

These are tested every quarter in the full-failover drills. The measured P95 is reported on the DR readiness dashboard.

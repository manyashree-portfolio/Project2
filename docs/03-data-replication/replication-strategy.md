# Data Replication Strategy - PaySecure Gateway

Scope: every stateful component in the multi-region design: Aurora PostgreSQL, DynamoDB, ElastiCache Redis, MSK Kafka and S3. Companion file: `sequence-diagrams.md` (Mermaid diagrams for the five required flows; each flow includes all five components).

Baseline numbers used throughout: 3.2M transactions/day, 500 crore INR/day (average about 1,562 INR per transaction), peak 1,200 TPS, average about 37 TPS over 24 h, P99 180 ms, NPCI ceiling 300 ms, Mumbai-Hyderabad RTT 15-25 ms, Mumbai-Singapore RTT 50-80 ms, RPO target < 60 s.

## 1. Summary of Decisions
| Component | Mechanism | Sync or async | Typical lag | Consistency | Conflict handling |
|---|---|---|---|---|---|
| Aurora PostgreSQL 15.4 | Aurora Global Database (storage-level) | Async | < 1 s | Strong on the primary, eventual on the secondary | None needed: one writer per cluster |
| DynamoDB | Global Tables | Async | < 1 s | Strong in the writing region, eventual in the replica | Last-writer-wins, avoided by single-region writes per key |
| ElastiCache Redis | Global Datastore | Async | Seconds | Eventual | None: secondary is read-only until promoted; cache is rebuildable |
| MSK Kafka | MSK Replicator (or MirrorMaker 2) | Async | Seconds to minutes | Eventual | Offset translation, consumers idempotent |
| S3 | Cross-Region Replication with RTC | Async | Seconds, SLA 15 min | Eventual | Versioning, no concurrent writers per object |

All five are asynchronous. The reasoning follows in Section 2.

## 2. Synchronous vs Asynchronous: Latency Budget
The NPCI ceiling is 300 ms end-to-end and the current P99 is 180 ms, so the budget for added latency is **120 ms**.

Synchronous replication adds one cross-region round trip plus the remote commit time to every acknowledged write:

| Link | RTT | Remote commit | Added latency per sync write | P99 after sync | Within 300 ms? |
|---|---|---|---|---|---|
| Mumbai - Hyderabad | 15-25 ms | 2-5 ms | 17-30 ms | 197-210 ms | Yes (90 ms spare) |
| Mumbai - Singapore | 50-80 ms | 2-5 ms | 52-85 ms | 232-265 ms | Barely (35 ms spare) |

A payment path performs several dependent writes (idempotency key, transaction record, status update), so the real impact multiplies. With 3 sequential synchronous writes to Hyderabad, the added latency is 3 x (17-30) = **51-90 ms**, giving a P99 of **231-270 ms**, which leaves only 30-69 ms of headroom and no margin for the evening settlement peak. With Singapore it would be 156-255 ms added, which breaks the 300 ms ceiling. Synchronous replication is therefore *technically possible* to Hyderabad for a single write, but unsafe for the full transaction path, and none of the five AWS services offers it as a managed option for Aurora PostgreSQL global databases, DynamoDB Global Tables, ElastiCache Global Datastore or MSK Replicator.

**Decision: asynchronous replication everywhere, with strict lag monitoring.** The data-loss exposure is the replication lag multiplied by the write rate:

| Lag | At average load (37 TPS) | At peak (1,200 TPS) |
|---|---|---|
| 1 s | 37 transactions, about 0.58 lakh INR | 1,200 transactions, about 18.75 lakh INR |
| 5 s | 185 transactions, about 2.9 lakh INR | 6,000 transactions, about 93.8 lakh INR |
| 60 s (RPO limit) | 2,220 transactions, about 34.7 lakh INR | 72,000 transactions, about 11.25 crore INR |

Typical lag below 1 second keeps real exposure to about 1,200 transactions at the very worst moment of the year. The RPO limit of 60 seconds is protected by alerts well before it is reached (Section 8).

**Evening batch settlement.** During batch settlement, write IOPS can triple (BCRB Challenge 4). Synchronous replication would raise latency at exactly that time, which is a further reason it is rejected. With asynchronous replication, the added risk is a larger lag. Control: the settlement job reads the replication-lag metric and applies backpressure. If Aurora global lag exceeds 5 seconds, batch writers pause or reduce concurrency until lag drops below 2 seconds. This caps the batch-time RPO at about 5-10 seconds, still far below 60 seconds.

## 3. CAP Theorem and PACELC Implications
- **Partition behaviour (CAP).** During a network partition between regions, the money-moving path chooses **Consistency over Availability (CP)**: only one region is the writer for a given dataset, and the other refuses writes instead of accepting divergent ones. A refused write costs a retry. A divergent write costs a double payment or a settlement break. Components where stale or missing data is harmless (Redis cache, analytics, logs) choose **Availability (AP)**.
- **No partition (PACELC "else").** The design trades consistency for latency (EL): asynchronous replication keeps the write path at 180 ms and accepts that the replica trails by up to about 1 second.
- **Split-brain** (two regions both believing they are the writer) is the risk the CRO cares most about. It is prevented by construction (single writer per dataset), by **fencing** (the old primary is demoted, its Route 53 record withdrawn and its writer security group closed before the new primary is promoted), and by a **decision rule** that promotion requires the peer region to be confirmed unreachable from an independent vantage point (a Singapore-hosted probe plus an external synthetic monitor). Resolution after a suspected split-brain is in RB-05.

## 4. Aurora PostgreSQL (Aurora Global Database)
- **Mechanism and justification.** Storage-level replication from the primary cluster in Mumbai to a secondary cluster in Hyderabad. Replication happens in the storage layer and does not consume database engine CPU, so write latency is unchanged. Lag is typically under 1 second. Recovery uses a managed failover of the global cluster (planned switchover for drills, failover with data-loss allowance for an unplanned regional outage).
- **Sync vs async.** Asynchronous (Section 2). RPO is the lag at failure time.
- **Consistency.** Strongly consistent on the writer. Hyderabad readers are eventually consistent and are used only for reporting and for the DR readiness checks.
- **Conflict resolution.** Not applicable: one writer. In the active-active design, two separate global clusters give each region a writer for its own merchants (see `active-active-design.md`).
- **Failure modes and responses.**
  1. Lag grows (network congestion, heavy batch): alert, apply batch backpressure.
  2. Replication stops (partition or secondary fault): P1 alert at lag above 500 ms for 2 checks; if lag is above 60 s at the time of a regional failure, the Incident Commander decides between promoting with data loss and waiting.
  3. Primary region fails: failover with data-loss allowance to Hyderabad, writer endpoint updated, reconciliation of the last seconds against bank references.
  4. Logical corruption replicates to the secondary: point-in-time recovery or a copy-on-write database clone plus manual correction (RB-02). Aurora PostgreSQL does not support Backtrack, which is Aurora MySQL only.
- **Monitoring.** CloudWatch metric `AuroraGlobalDBReplicationLag` (milliseconds), `AuroraGlobalDBProgressLag`, `AuroraGlobalDBDataTransferBytes`. Alert: lag above 500 ms for 2 consecutive 60-second checks = P1.
- **Latency impact if it were synchronous:** +17-30 ms per commit (Section 2).

## 5. DynamoDB (Global Tables)
- **Mechanism and justification.** A replica of the session and idempotency tables in Hyderabad. Global Tables replicate item-level changes, normally within a second, and both replicas accept writes, so no promotion step is needed in a failover.
- **Sync vs async.** Asynchronous multi-Region eventual consistency. Where AWS offers multi-Region strong consistency for Global Tables in these regions, it would give RPO 0 for idempotency keys at the cost of one cross-region round trip per write (about 15-25 ms). This must be verified for ap-south-1 and ap-south-2 availability before use. Even without it, the residual risk (a key written in the last second before a regional failure) is covered by transaction reconciliation against bank reference IDs.
- **Consistency.** Strongly consistent reads are available only in the region where the item was written. Reads in the other region are eventually consistent.
- **Conflict resolution.** Last-writer-wins by timestamp. This is unsafe for idempotency records if two regions write the same key at the same moment. Control: **single-region writes per key** (the application only writes in the active region in active-passive, and only in the merchant's home region in active-active), so no concurrent writers exist. Keys are designed as `merchantId#idempotencyKey` with a conditional write (`attribute_not_exists`) so a duplicate is rejected locally.
- **Failure modes.** Replication delay (idempotency miss on failover), replication halt (replica stale), accidental delete replicated everywhere (mitigation: point-in-time recovery, deletion protection), throttling due to replicated write capacity (each replicated write consumes replicated WCUs, so replica capacity must match, at about 1.5x cost per WCU).
- **Monitoring.** `ReplicationLatency` per replica table. Alert above 1,000 ms for 3 consecutive checks = P1. Also `ConditionalCheckFailedRequests` spikes to detect duplicate-key conflicts.
- **Latency impact if synchronous:** +15-25 ms per write.

## 6. ElastiCache Redis (Global Datastore)
- **Mechanism and justification.** A secondary replication group in Hyderabad receives asynchronous replication from the Mumbai primary. It is read-only until promoted.
- **Sync vs async.** Asynchronous. The cache holds merchant configuration, rate-limit counters and frequently used lookups. Everything in it can be rebuilt from Aurora and DynamoDB, so RPO is not a concern for the cache.
- **Consistency.** Eventual. Replica reads can be seconds stale.
- **Conflict resolution.** None: single writer. On failover the secondary is promoted, and the application warms the cache.
- **Failure modes and responses.** Replication lag (stale configuration, mitigated by short TTLs of 60-300 s on configuration keys), promotion failure (retry, or create a fresh cluster and warm it from the database), cold cache after failover (a "thundering herd" of reads on Aurora). Mitigations: pre-warm the 5,000 most active merchants' configuration, request coalescing and jittered TTLs.
- **Rate limits during failover.** Counters do not need to be accurate across a failover. The promoted cache starts with empty counters, which briefly permits more traffic than the limit, so WAF rate rules stay as the outer guard.
- **Monitoring.** `GlobalDatastoreReplicationLag`. Alert above 2,000 ms for 3 consecutive checks = P2.
- **Latency impact if synchronous:** not offered, and a cache write that waited 15-25 ms would defeat the purpose of the cache.

## 7. MSK Kafka (MSK Replicator / MirrorMaker 2)
- **Mechanism and justification.** MSK Replicator copies topics, and synchronises consumer-group offsets, from the Mumbai cluster to a 6-broker cluster in Hyderabad. It is fully managed, scales automatically, and avoids running MirrorMaker 2 on EKS (extra operational burden for an 8-person team). MirrorMaker 2 remains the fallback if a required feature is missing.
- **Sync vs async.** Asynchronous, with lag from seconds to minutes depending on throughput. At the peak rate of 50,000 messages/s and an assumed average of 1 KB per message, the replicator carries about 50 MB/s (about 400 Mbps) and needs matching inter-region bandwidth. Cross-region data transfer is a significant line item in the cost model.
- **Consistency and ordering.** Ordering is preserved within a partition. Cross-partition ordering is not guaranteed (and is not relied on). Replication is at-least-once, so the same event can appear twice after a failover. All consumers (settlement-engine, webhook-dispatcher, notification-service, audit-logger) must be **idempotent**, keyed by transaction ID plus event type.
- **Topic naming.** In active-passive, replicated topic names are kept identical so consumers need no configuration change on failover. In active-active, topic names carry a region prefix to prevent replication loops.
- **Conflict resolution.** Not applicable (append-only log).
- **Failure modes.** Replicator lag grows (backlog on failover means missed webhook or settlement events), replicator halt, offset translation gap (consumers re-read some messages), broker disk failure on the source. Recovery: consumers resume from the translated offsets and reprocess idempotently. The 7-day retention on both clusters allows replay.
- **Monitoring.** `ReplicationLatency` and `MessageLag` for the replicator. Alert: lag above 10,000 messages for 5 minutes = P2. At 50,000 messages/s, 10,000 messages is about 0.2 seconds of traffic, so the threshold means the replicator has fallen meaningfully behind rather than that it is lagging by seconds.
- **Latency impact:** zero on the producer path (producers write to the local cluster only).

## 8. S3 (Cross-Region Replication)
- **Mechanism and justification.** Replication rules copy new objects (backups, exports, audit archives, reports) from Mumbai buckets to Hyderabad buckets. Replication Time Control (RTC) gives a 15-minute SLA for 99.99% of objects and emits replication metrics and events. Versioning is mandatory on both buckets.
- **Sync vs async.** Asynchronous. S3 content is not on the latency-critical path.
- **Consistency.** Eventual between regions. Within a region S3 is strongly consistent.
- **Conflict resolution.** Not applicable: single writer per prefix. Delete markers: replication of delete markers is **disabled** for backup buckets so that an accidental or malicious delete in Mumbai cannot remove the Hyderabad copy. Object Lock (compliance mode) protects audit archives.
- **Failure modes.** Replication backlog, a KMS key or IAM permission change that silently stops replication, bucket-policy drift. Mitigation: replication failure metrics and S3 event notifications, and weekly restore tests.
- **Encryption.** Objects are encrypted with multi-Region KMS keys, so the replica can be decrypted in Hyderabad without a cross-region KMS call.
- **Monitoring.** `OperationsPendingReplication`, `ReplicationLatency`, `OperationsFailedReplication`. Alert: any failed replication or pending operations older than 15 minutes = P2.

## 9. Cross-Cutting Controls
1. **Data residency.** Every replica is in an Indian region. Replication traffic uses the AWS backbone between ap-south-1 and ap-south-2, encrypted with TLS 1.3, and never crosses an Indian border. Singapore receives only non-PII operational data.
2. **Encryption.** AES-256 at rest with KMS multi-Region keys; TLS 1.3 in transit (see `docs/07-data-sovereignty`).
3. **Reconciliation after failover.** Within the first hour after failover, a reconciliation job compares last-committed transaction IDs and amounts against bank and NPCI references for the last 5 minutes before the failure, and lists transactions missing from the new primary (possible loss) or present twice (possible duplicate).
4. **Failback.** After the original region recovers, it is re-attached as a *secondary*, the data drift is overwritten by replication from the new primary, and a planned switchover back to Mumbai is scheduled in a low-traffic window. Data written in Mumbai but never replicated is extracted from backups and reconciled manually before the overwrite (see the failback flow in `sequence-diagrams.md`).
5. **Drift detection.** Weekly automated comparison of schema versions, table definitions, replication configuration and IAM policies between regions.

### 9.4 In-flight transactions during a failover (BCRB Challenge 1)

A payment that is mid-flight when Mumbai fails ends in one of three states, and the design makes each safe:

1. **Not yet committed to Aurora.** The merchant sees a timeout or connection error, never a success. The merchant retries with the same idempotency key. The key was written to DynamoDB only with the transaction, so the retry is processed once in Hyderabad.
2. **Committed and replicated.** Hyderabad already has the row and the key (replication lag about 1 s). A retry returns the original result and does not charge again.
3. **Committed in Mumbai but not yet replicated (inside the RPO window).** The retry is treated as new. Before the bank or NPCI call, payment-api checks the bank or NPCI status by the transaction reference, and the post-failover reconciliation compares the last 5 minutes against bank and NPCI records within 1 hour. A debit with no recorded success is reversed through the settlement process.

Success is returned to the merchant only after the commit, so the customer's money moves only for transactions that have a recorded outcome or are reconciled afterwards.

## 10. Alert Summary
| Component | Metric | Threshold | Severity |
|---|---|---|---|
| Aurora Global DB | Replication lag | > 500 ms for 2 consecutive checks | P1 |
| DynamoDB Global Table | Replication latency | > 1,000 ms for 3 consecutive checks | P1 |
| ElastiCache Global Datastore | Replication lag | > 2,000 ms for 3 consecutive checks | P2 |
| MSK Replicator | Message lag | > 10,000 messages for 5 minutes | P2 |
| S3 CRR | Pending or failed replication | any failure, or backlog > 15 min | P2 |
| DR readiness composite | Any component unhealthy | any | P1 |

# Replication Sequence Diagrams (Mermaid)

Active-passive design: Mumbai (ap-south-1, `_M`) is primary, Hyderabad (ap-south-2, `_H`) is the standby. These diagrams render natively on GitHub.

**Component coverage.** Every diagram includes all five stateful components, so each has at least one sequence diagram.

| Component | Flow 1 Write | Flow 2 Read | Flow 3 Failover write | Flow 4 Failover read | Flow 5 Failback |
|---|---|---|---|---|---|
| Aurora PostgreSQL | yes | yes | yes | yes | yes |
| DynamoDB | yes | yes | yes | yes | yes |
| ElastiCache Redis | yes | yes | yes | yes | yes |
| MSK Kafka | yes | yes | yes | yes | yes |
| S3 | yes | yes | yes | yes | yes |

---

## Flow 1: Normal Write Path (primary region)
A payment is processed in Mumbai. The merchant gets a response after the local commit. All cross-region replication is asynchronous and off the request path, so P99 stays at about 180 ms.

```mermaid
sequenceDiagram
    autonumber
    participant C as Merchant
    participant API as payment-api (Mumbai)
    participant RED_M as Redis (Mumbai primary)
    participant DDB_M as DynamoDB (Mumbai)
    participant AUR_M as Aurora writer (Mumbai)
    participant MSK_M as MSK (Mumbai)
    participant S3_M as S3 (Mumbai)
    participant AUR_H as Aurora secondary (Hyderabad)
    participant DDB_H as DynamoDB replica (Hyderabad)
    participant RED_H as Redis secondary (Hyderabad)
    participant MSK_H as MSK (Hyderabad)
    participant S3_H as S3 replica (Hyderabad)

    C->>API: POST /payments with Idempotency-Key
    API->>RED_M: GET merchant config and rate-limit counter
    RED_M-->>API: config and counter under limit
    API->>DDB_M: conditional PUT idempotency key (attribute_not_exists)
    DDB_M-->>API: OK, key is new
    API->>AUR_M: INSERT transaction and COMMIT
    AUR_M-->>API: commit OK
    API->>MSK_M: publish txn-created event
    API->>S3_M: store receipt object (via audit-logger)
    API-->>C: 200 success (P99 about 180 ms)

    Note over AUR_M,S3_H: Asynchronous replication, off the request path
    AUR_M-)AUR_H: storage-level replication, lag under 1 s
    DDB_M-)DDB_H: Global Tables replication, lag under 1 s
    RED_M-)RED_H: Global Datastore replication, lag seconds
    MSK_M-)MSK_H: MSK Replicator copies topic and offsets, lag seconds
    S3_M-)S3_H: Cross-Region Replication with RTC
```

---

## Flow 2: Normal Read Path (both regions)
Customer-facing reads are served from Mumbai. Hyderabad serves only internal reads (reporting, DR readiness, synthetic checks), which proves the standby is current without sending it production traffic.

```mermaid
sequenceDiagram
    autonumber
    participant C as Merchant
    participant API_M as payment-api (Mumbai)
    participant RED_M as Redis (Mumbai)
    participant DDB_M as DynamoDB (Mumbai)
    participant AUR_M as Aurora (Mumbai writer or reader)
    participant MSK_M as MSK (Mumbai)
    participant S3_M as S3 (Mumbai)
    participant MON as DR readiness monitor (Hyderabad)
    participant AUR_H as Aurora replica (Hyderabad)
    participant DDB_H as DynamoDB replica (Hyderabad)
    participant RED_H as Redis secondary (Hyderabad)
    participant MSK_H as MSK (Hyderabad)
    participant S3_H as S3 replica (Hyderabad)

    rect rgb(235, 245, 255)
    Note over C,S3_M: Customer read in the primary region
    C->>API_M: GET /payments/{id}
    API_M->>RED_M: GET cached transaction
    alt cache hit
        RED_M-->>API_M: transaction status
    else cache miss
        API_M->>AUR_M: SELECT transaction (reader endpoint)
        AUR_M-->>API_M: row
        API_M->>RED_M: SET with TTL
    end
    API_M->>DDB_M: GET idempotency record (strongly consistent, home region)
    DDB_M-->>API_M: record
    API_M-->>C: 200 status
    API_M->>S3_M: GET receipt on request
    end

    rect rgb(235, 255, 240)
    Note over MON,S3_H: Internal reads in the standby region (every 30 to 60 s)
    MON->>AUR_H: SELECT newest committed transaction timestamp
    AUR_H-->>MON: timestamp (compare with primary, gives lag)
    MON->>DDB_H: GET synthetic key (eventually consistent)
    DDB_H-->>MON: record present
    MON->>RED_H: GET synthetic key (read-only replica)
    RED_H-->>MON: value present
    MON->>MSK_H: read replicated heartbeat topic and consumer group offset
    MSK_H-->>MON: heartbeat age
    MON->>S3_H: HEAD synthetic object
    S3_H-->>MON: object present
    MON-->>MON: publish DR-readiness composite metric (alert if any lag over threshold)
    end
```

---

## Flow 3: Failover Write Path (secondary promoted)
Mumbai is lost. DNS flips to Hyderabad within the first minute while the controller promotes the data stores in parallel. Until Hyderabad is write-ready, writes receive HTTP 503 with Retry-After, and the merchant retries with the same idempotency key.

```mermaid
sequenceDiagram
    autonumber
    participant C as Merchant
    participant R53 as Route 53
    participant CTL as Failover controller
    participant API_H as payment-api (Hyderabad)
    participant AUR_H as Aurora (Hyderabad)
    participant DDB_H as DynamoDB (Hyderabad)
    participant RED_H as Redis (Hyderabad)
    participant MSK_H as MSK (Hyderabad)
    participant S3_H as S3 (Hyderabad)

    Note over R53,CTL: T+0 Mumbai fails. T+30 s three health checks have failed
    R53->>R53: mark Mumbai unhealthy, serve Hyderabad record (TTL 30 s)
    R53-)CTL: health-check alarm triggers failover
    CTL->>CTL: T+45 s verify lag within limits and peer unreachable, fence Mumbai

    par Promotion in parallel (about 120 s)
        CTL->>AUR_H: failover-global-cluster with allow-data-loss
        AUR_H-->>CTL: Hyderabad cluster is now writer (60 to 90 s)
    and
        CTL->>RED_H: failover-global-replication-group
        RED_H-->>CTL: promoted to primary (30 to 60 s)
    and
        CTL->>MSK_H: point producers and consumers to Hyderabad bootstrap servers
        MSK_H-->>CTL: consumers resume from translated offsets
    and
        CTL->>API_H: scale EKS node group and deployments to production size
        API_H-->>CTL: pods ready (90 to 120 s)
    end

    Note over C,API_H: DNS has already moved. Writes retry until write-ready
    C->>API_H: POST /payments with Idempotency-Key
    API_H-->>C: 503 Retry-After 5 (write gate closed)
    CTL->>API_H: set write_ready = true after test write passes
    C->>API_H: retry POST /payments with same Idempotency-Key
    API_H->>DDB_H: conditional PUT idempotency key
    alt key already replicated (request was committed in Mumbai)
        DDB_H-->>API_H: key exists, return stored result
        API_H-->>C: 200 original result (no duplicate charge)
    else key not present
        DDB_H-->>API_H: OK, key is new
        API_H->>AUR_H: INSERT transaction and COMMIT
        AUR_H-->>API_H: commit OK
        API_H->>MSK_H: publish txn-created event
        API_H->>S3_H: store receipt object
        API_H-->>C: 200 success
    end
    Note over C,S3_H: T+2 min 45 s first successful write. T+3 min 25 s verified
```

---

## Flow 4: Failover Read Path (secondary serving)
After promotion, reads are served from Hyderabad. A transaction committed in Mumbai but not yet replicated before the failure will not be found, which is the RPO window. A reconciliation job handles those.

```mermaid
sequenceDiagram
    autonumber
    participant C as Merchant
    participant API_H as payment-api (Hyderabad, now primary)
    participant RED_H as Redis (promoted)
    participant DDB_H as DynamoDB (Hyderabad)
    participant AUR_H as Aurora writer (Hyderabad)
    participant MSK_H as MSK (Hyderabad)
    participant S3_H as S3 (Hyderabad)
    participant REC as reconciliation-worker

    C->>API_H: GET /payments/{id}
    API_H->>RED_H: GET cached transaction
    alt cache hit (replicated before failure)
        RED_H-->>API_H: transaction status
        API_H-->>C: 200 status
    else cache miss (cold cache after promotion)
        API_H->>AUR_H: SELECT transaction by id
        alt row found
            AUR_H-->>API_H: row
            API_H->>RED_H: SET with jittered TTL
            API_H-->>C: 200 status
        else row not found (inside the RPO window, under 1 s of writes)
            AUR_H-->>API_H: no row
            API_H->>DDB_H: GET idempotency record (now local and writable)
            DDB_H-->>API_H: record or none
            API_H-->>C: 404 or 202 pending, merchant told to query again
            API_H-)REC: flag id for reconciliation with bank reference
        end
    end

    Note over MSK_H,S3_H: Background services after promotion
    MSK_H-)REC: consumers resume from translated offsets (idempotent reprocessing)
    REC->>AUR_H: compare last 5 minutes of transactions with bank and NPCI references
    REC->>S3_H: write reconciliation report (immutable, retained for audit)
    REC-)C: merchant webhook for corrected status
```

---

## Flow 5: Data Reconciliation After Failback
The original region (Mumbai) recovers. It is rebuilt as a *secondary*, any data that was written in Mumbai but never replicated is recovered and reconciled, and a planned switchover returns the primary role during a low-traffic window.

```mermaid
sequenceDiagram
    autonumber
    participant OPS as Incident Commander and DBA
    participant AUR_M as Aurora (Mumbai, recovered)
    participant AUR_H as Aurora (Hyderabad, current primary)
    participant DDB_M as DynamoDB (Mumbai)
    participant DDB_H as DynamoDB (Hyderabad)
    participant RED_M as Redis (Mumbai)
    participant RED_H as Redis (Hyderabad)
    participant MSK_M as MSK (Mumbai)
    participant MSK_H as MSK (Hyderabad)
    participant S3_M as S3 (Mumbai)
    participant S3_H as S3 (Hyderabad)
    participant REC as reconciliation-worker

    OPS->>AUR_M: verify region healthy, keep Mumbai out of DNS
    OPS->>AUR_M: export unreplicated transactions after last replicated LSN or timestamp
    AUR_M-->>REC: orphan transaction list
    REC->>AUR_H: check each orphan against bank reference and transaction id
    alt orphan not present in Hyderabad
        REC->>AUR_H: replay as a reconciled transaction or refund, with audit note
    else already present
        REC-->>REC: mark duplicate, no action
    end
    OPS->>AUR_M: re-attach Mumbai as secondary cluster of the global database
    AUR_H-)AUR_M: full resync, Mumbai data overwritten by primary
    DDB_H-)DDB_M: Global Tables catch up (replica table resumes)
    RED_H-)RED_M: rebuild Global Datastore secondary in Mumbai
    MSK_H-)MSK_M: reverse MSK Replicator, copy backlog and offsets to Mumbai
    S3_H-)S3_M: replicate objects created during the outage
    OPS->>AUR_H: verify lag under 1 s on all components for 30 minutes
    OPS->>AUR_H: planned switchover to Mumbai (no data loss) in a low-traffic window
    AUR_H-->>AUR_M: Mumbai becomes writer
    OPS->>RED_H: promote Mumbai Redis, then switch DNS back with 30 s TTL
    OPS->>REC: run final reconciliation and sign-off report
    REC->>S3_M: store failback report (immutable)
```

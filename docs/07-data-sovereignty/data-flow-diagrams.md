# Data Flow Diagrams - Where Each Data Category Lives and Moves

These diagrams show, for each of the six data categories defined in the brief (A3.6), where the data is stored and how it moves in normal operation and during a failover. They support the compliance matrix (`compliance-matrix.md`) and answer BCRB Challenge 5 ("show me exactly where cardholder data resides, at rest and in transit, and whether it ever crosses a non-Indian path").

Legend: solid arrows are allowed flows. Every payment data path stays inside the two Indian regions, ap-south-1 (Mumbai) and ap-south-2 (Hyderabad).

## 1. Category map

```mermaid
flowchart TB
  subgraph MUM["ap-south-1 Mumbai (primary)"]
    CDE["CDE: tokenisation-service, Aurora CDE cluster<br/>(Cat 1 Cardholder Data)"]
    TX["Aurora, DynamoDB, MSK<br/>(Cat 2 Transaction, Cat 3 Merchant)"]
    OPS["Prometheus, ELK, Jaeger, CloudTrail<br/>(Cat 4 Operational: complete copy)"]
    CFG["Git, Terraform state, ConfigMaps<br/>(Cat 5 Configuration)"]
  end
  subgraph HYD["ap-south-2 Hyderabad (standby)"]
    CDE2["Aurora secondary, tokenisation standby<br/>(Cat 1)"]
    TX2["Aurora, DynamoDB, MSK replicas<br/>(Cat 2, 3)"]
    OPS2["Log and metric replicas<br/>(Cat 4)"]
    CFG2["Config replicas (Cat 5)"]
  end
  SG["Singapore (non-payment account)<br/>Cat 4 redacted copy, Cat 5, Cat 6 anonymised"]
  AN["Analytics store: aggregated, anonymised (Cat 6)"]
  CDE -->|"TLS 1.3, KMS-encrypted storage replication"| CDE2
  TX -->|"Aurora global, Global Tables, MSK Replicator"| TX2
  OPS --> OPS2
  CFG --> CFG2
  OPS -->|"PII redaction filter"| SG
  TX -->|"aggregate then irreversibly anonymise"| AN
  AN --> SG
  CDE -. "never" .- SG
  TX -. "never" .- SG
```

## 2. Cardholder data (Category 1): normal and failover path

```mermaid
sequenceDiagram
  participant M as Merchant / customer
  participant ALB as ALB + WAF (Mumbai)
  participant API as payment-api
  participant TOK as tokenisation-service (CDE)
  participant DB as Aurora CDE cluster (Mumbai)
  participant KMS as KMS key (Mumbai)
  participant DB2 as Aurora secondary (Hyderabad)
  participant KMS2 as KMS replica key (Hyderabad)
  M->>ALB: HTTPS TLS 1.3 (card data in request)
  ALB->>API: mTLS (Istio)
  API->>TOK: gRPC, mTLS, only path into the CDE
  TOK->>KMS: encrypt PAN (AES-256 envelope)
  TOK->>DB: store token vault record (encrypted)
  DB-->>DB2: storage-level replication, TLS 1.3, same ciphertext
  Note over DB2,KMS2: Replica key decrypts only inside Hyderabad
  Note over M,DB2: Failover: DNS moves clients to Hyderabad ALB. No data is copied anywhere new, no non-Indian network path exists
```

Where CHD exists: only in the CDE namespace (`paysecure-cde`), in the Aurora CDE cluster in both Indian regions, and in KMS-encrypted backups in Indian S3 buckets. It is encrypted at rest with AES-256 under `alias/paysecure-cde` and in transit with TLS 1.3 or mTLS. NetworkPolicy and PCI DSS segmentation (Requirement 1) restrict access to the payment-api and tokenisation-service.

## 3. Transaction and merchant data (Categories 2 and 3): replication and reconciliation

```mermaid
flowchart LR
  W["Write in Mumbai: payment-api to Aurora, idempotency key to DynamoDB, event to MSK"] --> R1["Aurora global replication (about 1 s)"]
  W --> R2["DynamoDB Global Tables (under 1 s)"]
  W --> R3["MSK Replicator (seconds)"]
  R1 --> H["Hyderabad copies"]
  R2 --> H
  R3 --> H
  H --> F{"Failover?"}
  F -- "yes" --> P["Promote Hyderabad; reconcile last 5 min against bank and NPCI references"]
  F -- "no" --> S["Standby, read-only"]
  P --> B["Failback later: replicate back to Mumbai, reconcile, switch"]
```

All three stores replicate inside India. Merchant bank details are field-level encrypted before they are stored, so replicas never hold them in clear text.

## 4. Operational data (Category 4): redaction before any cross-border copy

```mermaid
flowchart LR
  APP["Applications, nodes, AWS services"] --> COL["Collectors in Mumbai and Hyderabad"]
  COL --> ELK["ELK / Prometheus / Jaeger / S3 log buckets (complete copy, India, 180 days minimum)"]
  ELK --> RED["Redaction filter: drops PAN, tokens, VPA, mobile, email, merchant IDs"]
  RED --> CHK{"Pattern check passes?"}
  CHK -- "yes" --> SG["Singapore operational copy (non-PII)"]
  CHK -- "no" --> Q["Quarantine and alert (P2)"]
```

PagerDuty and other third-party tools receive alarm name, severity and resource ID only.

## 5. Configuration and analytics data (Categories 5 and 6)

```mermaid
flowchart LR
  GIT["Git repository: Terraform, manifests, feature flags"] --> REG["All regions"]
  TXN["Transaction data (India)"] --> AGG["Aggregate: volumes, trends, no identifiers"]
  AGG --> ANON["Irreversible anonymisation, DPO review"]
  ANON --> ALL["Analytics store, any region"]
```

Secrets are not configuration data: they live in Secrets Manager with India-only replication, encrypted under `alias/paysecure-data`.

## 6. Residency checkpoints during a failover

| Step | Checkpoint | Evidence |
|---|---|---|
| Before | Weekly sovereignty check passed within 7 days | `scripts/health-checks/sovereignty-check.sh` output |
| Promotion | Both Aurora clusters, DynamoDB replicas, Redis, MSK and S3 are in Indian regions | Terraform state and AWS describe calls |
| During | Traffic path: client to Hyderabad ALB to Hyderabad cluster; no peering to non-Indian networks | VPC flow logs, Transit Gateway route tables |
| After | Post-drill or post-incident Config query returns no resources outside ap-south-1 and ap-south-2 | `post-drill-reconcile.sh` |
| After | Operational copy in Singapore passed the redaction check | Pipeline quarantine report |

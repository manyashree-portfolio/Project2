# Terraform - PaySecure multi-region DR (Mumbai + Hyderabad)

| Path | Purpose |
|---|---|
| `envs/prod` | Production DR environment: Hyderabad standby plus cross-region replication for the existing Mumbai platform |
| `envs/org` | AWS Organizations guardrails (India-only Service Control Policy). Apply from the management account |
| `modules/networking` | Hyderabad VPC, private subnets, VPC endpoints, Transit Gateway |
| `modules/compute` | Hyderabad EKS cluster `paysecure-dr` and On-Demand Capacity Reservations |
| `modules/database` | Aurora Global Database `paysecure-global` (Mumbai writer, Hyderabad secondary) |
| `modules/dynamodb` | Global Tables `paysecure-idempotency`, `paysecure-sessions` |
| `modules/cache` | ElastiCache Redis Global Datastore `paysecure-redis-global` |
| `modules/messaging` | MSK clusters and MSK Replicator `paysecure-replicator` (used by RB-04) |
| `modules/storage` | Backup and audit buckets with cross-region replication and RTC (audit under Object Lock) |
| `modules/dns` | Route 53 health checks and failover records for `api.paysecure.in` |
| `modules/monitoring` | SNS alert topics in both regions, payment success-rate and latency alarms |
| `modules/security` | Multi-Region KMS keys (`alias/paysecure-cde`, `alias/paysecure-data`), WAF web ACL with the staged emergency rule, optional Shield Advanced; `waf-rules/` holds the RB-07 JSON files |
| `modules/cicd` | Clean CI/CD runner fleet and OIDC deploy role (used by RB-11) |
| `modules/guardrails` | The India-only SCP and the narrow Singapore operations exception |

Conventions: Terraform 1.5 or later, `required_providers` in every module, every variable has a description and a type, resources are tagged through provider `default_tags` (Project, Environment, CostCenter, DR-Tier, ManagedBy, DataClass), and state is stored in S3 with DynamoDB locking (`envs/prod/backend.tf`).

## Status - read before applying
- **Not applied and not validated with the Terraform CLI.** These files were syntax-parsed only. Run `terraform init && terraform validate && terraform plan` in a sandbox account first and fix any provider-version differences.
- The Mumbai platform already exists. Import existing resources (`terraform import`) before the first apply; do not let Terraform recreate production databases.
- Instance sizes, capacity splits, CIDRs, Kafka version and similar values are **assumptions** (marked `assumed` in `variables.tf`). Replace with real values.
- Everything stays in `ap-south-1` and `ap-south-2` (see `docs/07-data-sovereignty`).

## Usage
```
cd envs/prod
cp terraform.tfvars.example terraform.tfvars   # fill in real values
terraform init
terraform plan -out tfplan
terraform apply tfplan
```
Runbook-driven targeted applies: `-target=module.messaging` (RB-04) and `-target=module.cicd` (RB-11).

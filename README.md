# PaySecure Gateway - Multi-Region Disaster Recovery Architecture

A design, runbook and automation package for moving PaySecure's payment gateway from a single region to a **two-region, all-India** disaster recovery setup: **Mumbai (ap-south-1) primary, Hyderabad (ap-south-2) standby**.

**Targets:** uptime 99.92% -> 99.99% | RPO < 1 min | RTO < 5 min | payment data stored in India only.

> **Read this first**
> 1. **The project brief contains five deliberate errors.** They are documented, with sources, in `docs/deliberate-errors-found.md`. This repository uses the corrected values.
> 2. **Configs and scripts are not applied** to AWS or a cluster. They are syntax-checked only (see "Verification status").
> 3. **Some inputs are assumptions** (cost split by service, instance sizes, metric names, some clause numbers). They are marked where they appear and listed under "Open items".

## Baseline data used consistently across all documents
3.2M txns/day | 500 crore INR/day (about 1,562 INR per transaction) | 1,200 peak TPS (about 37 TPS 24-hour average, about 56 TPS over a 16-hour business day) | 180 ms P99 | 45,000 merchants | 8 crore INR/yr infrastructure | 42 engineers (8 on the platform team)

## The recommendation in one page
- **Design:** active-passive ("Hot" standby). Mumbai serves all traffic; Hyderabad holds a continuously replicated, ready-to-promote copy. Active-active was analysed and is not recommended now; the comparison matrix lists the triggers that would change that.
- **Failover time:** about 2 min 45 s to the first successful write in the nominal case (3 min 25 s fully verified). The documented RTO is 4 minutes, inside the 5-minute mandate. Data loss is bounded by replication lag (about 1 s for Aurora), under the 60 s RPO.
- **Cost:** the Hot tier is about 1.6x the current infrastructure spend. Cold and Warm tiers do not meet the RTO/RPO mandate. The cost-optimisation levers bring Hot to about 1.42x, still slightly above the 1.4x board budget; the cost summary explains why Warm is not the answer. The 8 crore total is from the brief; its split across AWS services is an assumption.
- **Data sovereignty:** categories 1 to 3 (cardholder, transaction, merchant data) never leave the two Indian regions; only redacted operational data, configuration and anonymised analytics may go to Singapore, as the brief allows. Enforced by Service Control Policies and replication guardrails.
- **Operations:** 12 scenario runbooks; an annual plan of 4 full-failover and 12 component drills; 52 weekly automated readiness runs.

## How the repository covers the brief
| Brief deliverable | Where | Brief minimum | This repository |
|---|---|---|---|
| Current-state architecture | `docs/01-current-state` (diagram .drawio + .png, document, FMEA with 24 failure modes) | 800 words | about 2,100 words |
| Multi-region design | `docs/02-multi-region-design` (two diagrams, two designs, comparison matrix with 10 dimensions, answers to all 10 BCRB challenges) | 2,000 words per configuration | about 2,200 (active-active) and 3,000 (active-passive) words |
| Data replication strategy | `docs/03-data-replication` | 1,500 words, sequence diagrams | about 2,700 words, Mermaid sequence diagrams |
| DNS failover and health checks | `docs/04-dns-failover` (YAML and JSON configs, timing diagram) | 800 words | about 1,400 words |
| 12 runbooks | `docs/05-runbooks` (10-section template, decision trees) | 5,000 words total | about 22,800 words total |
| Cost model and ROI | `docs/06-cost-analysis` (`cost-model.xlsx` with 301 formulas, summary, ROI) | 1,000 words | about 1,400 words |
| Data sovereignty mapping | `docs/07-data-sovereignty` (compliance matrix, data-flow diagrams) | 800 words | about 4,300 words |
| Annual DR drill plan | `docs/08-dr-drill-plan` (plan, success criteria, post-drill template) | 1,200 words | about 3,600 words |
| Deliberate errors | `docs/deliberate-errors-found.md` | all 5 errors | 5 primary findings and 12 additional discrepancies |
| Infrastructure as code | `configs/terraform`, `configs/kubernetes`, `configs/monitoring` | Terraform modules, Kubernetes manifests | 12 module folders; Deployments, HPA, PDB, NetworkPolicy; Prometheus, Alertmanager, Grafana |
| Scripts | `scripts/failover`, `scripts/health-checks`, `scripts/dr-drill` | n/a | Failover, checks, drill automation |

## Who should read what
| If you are... | Start with |
|---|---|
| Board, CRO or auditor | `docs/02-multi-region-design/comparison-matrix.md`, `docs/06-cost-analysis/cost-summary.md`, `docs/07-data-sovereignty/compliance-matrix.md` |
| Architect | `docs/01-current-state/`, `docs/02-multi-region-design/`, `docs/03-data-replication/`, `docs/04-dns-failover/` |
| On-call engineer | `docs/05-runbooks/README.md`, then the runbook for the scenario; `scripts/failover/` |
| Platform / SRE | `configs/`, `scripts/`, `docs/08-dr-drill-plan/` |
| Compliance officer | `docs/07-data-sovereignty/` (compliance matrix Section 9: open items), `docs/deliberate-errors-found.md` |

## Repository map
| Path | Contents |
|---|---|
| `docs/01-current-state` | Current single-region architecture, diagram, FMEA |
| `docs/02-multi-region-design` | Active-passive and active-active designs and diagrams, comparison matrix, BCRB challenge responses |
| `docs/03-data-replication` | Replication strategy for Aurora, DynamoDB, Redis, MSK, S3 and KMS; sequence diagrams |
| `docs/04-dns-failover` | DNS and health-check design, `health-check-config.yaml`, `route53-config.json`, timing diagram |
| `docs/05-runbooks` | RB-01 to RB-12: region failure, database corruption, DNS poisoning, Kafka failure, network partition, key compromise, DDoS, NPCI/UPI outage, certificate expiry, AZ power failure, ransomware, cascading failure |
| `docs/06-cost-analysis` | Cost model workbook, cost summary, ROI analysis |
| `docs/07-data-sovereignty` | Compliance matrix (six data categories against RBI, PCI DSS, NPCI, IT Act / CERT-In / DPDP) and data-flow diagrams |
| `docs/08-dr-drill-plan` | Annual drill plan, success criteria, post-drill report template |
| `docs/deliberate-errors-found.md` | The deliberate errors found in the brief |
| `configs/terraform` | `envs/prod`, `envs/org`; modules networking, compute, database, dynamodb, cache, messaging, storage, dns, monitoring, security (with `waf-rules/`), cicd, guardrails |
| `configs/kubernetes` | Namespaces, Deployments and Services, region ConfigMap, HPA/PDB, Istio circuit breaker, Kyverno signed-image policy, CDE network policy, DR overlay |
| `configs/monitoring` | Prometheus DR alert rules, Alertmanager routes, Grafana DR readiness dashboard |
| `scripts/` | `common.sh` helper; `failover/`, `health-checks/` (including the weekly readiness run), `dr-drill/`; all dry run by default |

How the pieces connect: the runbooks call files in `configs/` and `scripts/` by name (for example `fraud-detection-circuit-breaker.yaml` in RB-12, `verify-signed-images.yaml` in RB-11, `waf-emergency-block.json` in RB-07, `tls-client-matrix.sh` in RB-09, `module.messaging` in RB-04, `module.cicd` in RB-11). The drill plan schedules every drill the runbooks promise, in the month they name. The compliance matrix defines the controls that the Terraform guardrails and `sovereignty-check.sh` enforce.

## Verification status
| Item | What was checked | What was not |
|---|---|---|
| Documents | Required files exist; word minimums met; cross-references resolve; baseline figures consistent; Markdown code fences balanced; all runbooks follow the 10-section template | Not reviewed by a QSA, lawyer or the regulator |
| Cost model | Recalculates with 301 formulas and 0 errors | Service split and several unit prices are assumptions (for example inter-region transfer USD 0.086/GB); verify in the AWS Pricing Calculator |
| Regulatory references | RBI storage circular (DPSS.CO.OD.No.2785/06.08.005/2017-18), CERT-In directions of 28 April 2022, RBI Payment Aggregator Directions 2025 checked against public sources | PCI DSS, DPDP and IT Act clause numbers tagged `[C]` need confirmation; NPCI circular numbers are not public and are not filled in |
| Brief errors | Visa 2018 outage, HDFC 2020 outage and RBI action, PCI DSS notification rules checked against public sources; TPS arithmetic recomputed | The AWS April 2021 case study could not be verified |
| Terraform | All `.tf` files parse and pass `tofu fmt`; module inputs match module variables; every variable has a description and type | `validate` and `plan` could not run (provider registry not reachable); never applied |
| Kubernetes | `kustomize build` succeeds for the base and the DR overlay; required probes, requests and limits asserted | Not applied to a cluster; CRDs (Istio, Kyverno) not installed here |
| Monitoring, WAF | YAML and JSON parse; runbook-required values asserted | Metric names are assumptions; WAF files must be merged with the live web ACL |
| Scripts | `bash -n` and ShellCheck clean; failover script dry-run against stubbed commands | Never run against AWS |

## Open items
1. **Singapore.** The brief allows redacted non-PII operational data there. Counsel should confirm the redaction, and the complete ICT log copy must stay in India (CERT-In).
2. **Clause numbers** tagged `[C]` in the compliance matrix and the NPCI circular numbers need COMP / QSA confirmation.
3. **Brief-sourced figures** such as the RBI "RTO under 4 hours" could not be matched to a published instrument (`docs/deliberate-errors-found.md`, findings 7 to 9).
4. **DPDP commencement dates** and the applicability of the RBI IT Governance Master Direction to a non-bank payment aggregator are unconfirmed.
5. **AWS Hyderabad service parity:** confirm every service in the design is available in ap-south-2 before committing.
6. **Cost inputs:** replace the assumed service split with real billing data.
7. **Not built:** the AWS Fault Injection Service experiment template, the reconciliation CronJob and the weekly restore-test job that the drill scripts expect; the optional "Sandbox" bonus topics (multi-cloud DR, decision engine, VaR model) are not included.
8. **Proposed, not agreed:** drill abort thresholds, effort estimates and the business-hours drill gate; the CTO and BCRB should approve them.
9. **Route 53 health checkers** probe from outside India; the `/health/*` endpoints must never return payment data.

## Quick checks (from the repository root)
```
shellcheck -x scripts/*.sh scripts/*/*.sh                 # needs shellcheck
kustomize build configs/kubernetes/overlays/dr             # needs kustomize
cd configs/terraform/envs/prod && terraform init -backend=false && terraform validate
```
`terraform validate` downloads the AWS provider and registry modules; use a sandbox, not production credentials.

## Submission steps (from the brief, Day 14-15)
Keep the GitHub repository **private**, check that all Markdown renders on GitHub, then transfer the repository to `@ZethetaIntern` and send the notification email to the assessment board.

## Change history
See `CHANGELOG.md`.

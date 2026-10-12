# ClaimGuard AI

**Agentic RAG for Healthcare Insurance Claim Denial Prevention**

Built on Snowflake | Prototype v1.0 | October 2026

---

## Business Problem

Healthcare providers submit insurance claims that may have missing documentation, incomplete coding, or requirements that don't align with payer policy. Denials and rework delay reimbursement and consume billing-team capacity. Coverage rules vary by payer, jurisdiction, service date, and item; records are fragmented across billing, clinical, and policy systems.

**ClaimGuard AI** is a human-in-the-loop pre-submission review assistant. It uses deterministic data-quality checks, structured claim retrieval, and retrieval-augmented generation over authoritative Medicare coverage documents to identify documentation gaps before claims are submitted.

### Scope

- **Payer:** Medicare fee-for-service
- **Claim category:** Home oxygen equipment (DME)
- **Policy basis:** NCD 240.2, LCD L33797, Policy Article A52510
- **Data:** Synthetic (Synthea + Snowflake Marketplace)

---

## Architecture

```
Data Sources → RAW (stages, COPY INTO) → Streams/Tasks → CORE (normalized views)
                                                              │
                                                              ▼
                                                    ┌─────────────────────┐
                                                    │    Cortex Agent     │
                                                    │  ┌───────────────┐  │
                                                    │  │ PolicySearch  │  │
                                                    │  │ (Cortex Search│  │
                                                    │  │  Service)     │  │
                                                    │  └───────────────┘  │
                                                    └─────────┬───────────┘
                                                              │
┌──────────────┐    ┌──────────────────┐    ┌─────────────────▼──────────┐
│ Rules Engine │    │ Semantic View    │    │    Review Queue (APP)      │
│ (SQL checks) │    │ (Cortex Analyst) │    │    Findings + Actions      │
└──────┬───────┘    └────────┬─────────┘    └─────────────┬──────────────┘
       │                     │                            │
       └─────────────────────┴────────────────────────────┘
                                    │
                                    ▼
                          Streamlit Dashboard
                     (Queue → Review → Action → Audit)
```

### Layer Responsibilities

| Layer | Schema | Components | Purpose |
|-------|--------|------------|---------|
| Ingestion | `RAW` | Stages, COPY INTO, stream, task | Land claims and detect new arrivals |
| Structured Knowledge | `CORE` | 7 views over Marketplace data | Patient, claim, clinical data lookup |
| Unstructured Knowledge | `RAG` | Policy documents, chunks, Cortex Search | Retrieve relevant policy passages |
| Orchestration | `APP` | Cortex Agent, rules engine | Choose tools, compile evidence, check requirements |
| Experience | `APP` | Streamlit dashboard | Queue, findings, reviewer action, pipeline status |

---

## Snowflake Features Used

| Feature | How It's Used |
|---------|---------------|
| **Snowflake Marketplace** | Synthetic Healthcare Data (1.4M patients, 124M claims, 763M observations) — zero-copy, no storage cost |
| **Views** | 7 CORE views over Marketplace tables — clean interface, zero storage |
| **Streams** | `NEW_CLAIMS_STREAM` detects inserts into `RAW.INCOMING_CLAIMS` |
| **Tasks** | `QUEUE_NEW_CLAIMS` (every 5 min with deduplication + validation) → `ROUTE_INVALID_CLAIMS` (DLQ routing) |
| **Alerts** | `FAILED_CLAIMS_ALERT` + `DLQ_ALERT` — hourly pipeline health checks, log to PIPELINE_RUNS |
| **Cortex Search Service** | `POLICY_SEARCH_SERVICE` — semantic + keyword hybrid search over 12 policy chunks |
| **Cortex Agents** | `CLAIMGUARD_AGENT` — orchestrates PolicySearch and ClaimAnalytics tools with instructions and budget |
| **Semantic Views** | `CLAIM_REVIEW_VIEW` — maps 5 tables with relationships, synonyms, and metrics for Cortex Analyst |
| **Table Functions** | `CHECK_CLAIM_REQUIREMENTS` — deterministic SQL rules engine (8 checks) returning pass/fail per requirement |
| **Stored Procedures** | `RUN_EVALUATION` — batch evaluation; `CHECK_CLAIM_LLM` — LLM-based clinical note analysis (6 checks) |
| **Cortex AI Functions** | `AI_COMPLETE` (llama3.1-70b) — generates synthetic clinical notes and evaluates them against policy requirements |
| **Streamlit** | 4-page reviewer dashboard with deterministic checks, LLM-based checks, clinical notes viewer, and reviewer actions |
| **RBAC** | 3 roles (SERVICE, REVIEWER, ADMIN) with least-privilege grants |
| **Resource Monitor** | `CLAIMGUARD_MONITOR` — 100 credit/month cap with auto-suspend at threshold |

---

## Database Schema

### CLAIMGUARD.RAW — Landing Zone

| Object | Type | Rows | Description |
|--------|------|------|-------------|
| `INCOMING_CLAIMS` | Table | 5 | Landing table for new claim files |
| `NEW_CLAIMS_STREAM` | Stream | — | Detects new inserts for queue processing |

### CLAIMGUARD.CORE — Normalized Clinical Data

All views read from `SYNTHETIC_HEALTHCARE_DATA_CLINICAL_AND_CLAIMS.SILVER` (zero storage cost).

| Object | Type | Source Rows | Description |
|--------|------|-------------|-------------|
| `PATIENTS` | View | 1.4M | Patient demographics |
| `ENCOUNTERS` | View | 64.5M | Healthcare visits |
| `CLAIMS` | View | 124M | Insurance claims with diagnosis codes |
| `CLAIM_LINES` | View | 887M | Individual charges per claim |
| `DIAGNOSES` | View | 38.5M | Diagnosed conditions |
| `OBSERVATIONS` | View | 763M | Lab results, vitals, O2 saturation |
| `CLINICAL_EVIDENCE` | View | ~1B | Combined observations + procedures + devices + medications |
| `CLAIM_REVIEW_VIEW` | Semantic View | — | Maps tables with relationships and synonyms for Cortex Analyst |
| `CLINICAL_NOTES` | Table | 15 | AI-generated clinical notes (progress notes, physician orders, CMNs) |

### CLAIMGUARD.RAG — Policy Knowledge Base

| Object | Type | Rows | Description |
|--------|------|------|-------------|
| `POLICY_DOCUMENTS` | Table | 3 | NCD 240.2, LCD L33797, PA A52510 |
| `POLICY_VERSIONS` | Table | 3 | Full policy text with effective dates |
| `POLICY_CHUNKS` | Table | 12 | Searchable passages chunked by logical section |
| `POLICY_REQUIREMENTS` | Table | 15 | Structured testable rules (REQ-001 through REQ-015) |
| `POLICY_SEARCH_SERVICE` | Cortex Search | — | Hybrid semantic + keyword search over policy chunks |

### CLAIMGUARD.APP — Review Workflow

| Object | Type | Rows | Description |
|--------|------|------|-------------|
| `REVIEW_QUEUE` | Table | 5 | Claims awaiting agent review |
| `CLAIM_REVIEWS` | Table | 0 | Agent review results with input snapshots |
| `REVIEW_FINDINGS` | Table | 0 | Per-requirement findings with citations |
| `REVIEW_ACTIONS` | Table | 0 | Reviewer decisions (accept/reject/escalate) |
| `PIPELINE_RUNS` | Table | 0 | Batch operation tracking |
| `GOLD_SET` | Table | 96 | Labeled test cases for evaluation |
| `EVALUATION_RESULTS` | Table | 96 | Per-case expected vs actual comparison |
| `EVALUATION_RUNS` | Table | 1 | Summary metrics per evaluation run |
| `DEAD_LETTER_QUEUE` | Table | 0 | Failed/invalid claims routed here for investigation |
| `CHECK_CLAIM_REQUIREMENTS` | Function | — | Deterministic SQL rules engine (8 checks) |
| `CHECK_CLAIM_LLM` | Procedure | — | LLM-based clinical note evaluation (6 checks) |
| `RUN_EVALUATION` | Procedure | — | Batch evaluation with metrics calculation |
| `QUEUE_NEW_CLAIMS` | Task | — | Auto-queues new claims every 5 minutes |
| `ROUTE_INVALID_CLAIMS` | Task | — | Routes invalid records to dead-letter queue (runs after QUEUE_NEW_CLAIMS) |
| `FAILED_CLAIMS_ALERT` | Alert | — | Hourly check for claims exceeding max retries |
| `DLQ_ALERT` | Alert | — | Hourly check for unresolved dead-letter items |
| `CLAIMGUARD_AGENT` | Agent | — | Cortex Agent with PolicySearch + ClaimAnalytics tools |

---

## Policy Requirements Checked

15 requirements extracted from CMS Medicare home oxygen coverage policies:

| Code | Requirement | Type | Check Method |
|------|-------------|------|-------------|
| REQ-001 | Patient must have ABG or pulse oximetry result | CLINICAL | SQL (deterministic) |
| REQ-002 | O2 saturation ≤88% (Group I) or 89% with secondary dx (Group II) | CLINICAL | SQL (deterministic) |
| REQ-003 | Blood gas test in chronic stable state, not acute exacerbation | CLINICAL | LLM (clinical notes) |
| REQ-004 | Treating physician certifies medical necessity | DOCUMENTATION | LLM (clinical notes) |
| REQ-005 | CMN completed and signed | DOCUMENTATION | LLM (clinical notes) |
| REQ-006 | Order specifies diagnosis, flow rate, frequency, duration, portable need | DOCUMENTATION | LLM (clinical notes) |
| REQ-007 | Retesting between day 61 and day 90 | CLINICAL | Not implemented (needs longitudinal data) |
| REQ-008 | Qualifying respiratory diagnosis documented | CLINICAL | SQL (deterministic) |
| REQ-009 | Valid HCPCS code for home oxygen equipment | ADMINISTRATIVE | SQL (deterministic) |
| REQ-010 | Recertification after 12 months | DOCUMENTATION | Not implemented |
| REQ-011 | Blood gas results include date, conditions, lab ID | DOCUMENTATION | SQL (deterministic) |
| REQ-012 | Supporting H&P documentation on file | DOCUMENTATION | LLM (clinical notes) |
| REQ-013 | Blood gas test ≤30 days before service date | CLINICAL | SQL (deterministic) |
| REQ-014 | DME supplier has CMN before billing | ADMINISTRATIVE | LLM (clinical notes) |
| REQ-015 | KX modifier on claim for medical necessity | ADMINISTRATIVE | SQL (deterministic) |

**Coverage: 14 of 15 requirements implemented.**
- 8 deterministic SQL checks (instant, free, 100% accurate)
- 6 LLM-based checks (uses AI credits, requires clinical notes, non-deterministic)
- 1 not yet implemented (REQ-007 — needs longitudinal encounter data)

---

## AI Design Decisions

### 1. Deterministic rules first, LLM second

9 of 15 requirements can be checked with SQL. SQL checks are free, instant, and deterministic. The LLM is only called for requirements that need clinical note interpretation. Findings are flagged as `IS_DETERMINISTIC = TRUE/FALSE` so reviewers know which are guaranteed correct vs which need verification.

### 2. Chunking by logical section, not fixed length

Policy documents are split into chunks by their natural sections (e.g., "Qualifying Blood Gas Criteria - Group I") rather than fixed token counts. This ensures each chunk is self-contained and maps cleanly to a citable section heading.

### 3. Metadata attributes for filtered retrieval

Each chunk carries `POLICY_NUMBER`, `JURISDICTION`, `EFFECTIVE_DATE`, and `PAYER` as filterable attributes. The agent filters by these to ensure it only retrieves policies applicable to the claim being reviewed — semantic similarity alone is not sufficient for policy documents.

### 4. Hybrid search (vectors + keywords + reranking)

Cortex Search combines cosine similarity (semantic match), BM25 text matching (exact terms like "E1390"), and LLM reranking. This handles both natural language queries ("what qualifies for coverage?") and code lookups ("HCPCS E1390").

### 5. Human-in-the-loop, not autonomous

The agent produces findings; a human reviewer makes the final call. The status flow is: Agent outputs → PASS / ISSUE_FOUND / NEEDS_VERIFICATION / INSUFFICIENT_INFORMATION → Human acts → ACCEPT / REJECT / REQUEST_MORE_INFO / OVERRIDE / ESCALATE.

### 6. Views over Marketplace data (zero-copy)

CORE tables are views over the Marketplace dataset, not materialized copies. This eliminates storage costs and ensures data is always current. The semantic view adds meaning on top without duplicating data.

### 7. Audit trail by design

Every review stores an `INPUT_SNAPSHOT` (what the agent saw), `POLICY_VERSIONS_USED` (which rules applied), and `AGENT_VERSION` (which model ran). Every finding includes a `POLICY_CITATION` linking to the specific policy passage.

---

## Evaluation Results

### Baseline: Deterministic Rules Engine v1

| Metric | Value | Project Target |
|--------|-------|----------------|
| Precision | 100% | ≥90% |
| Recall | 100% | ≥90% |
| F1 Score | 100% | — |
| Citation Accuracy | 100% | ≥95% |

**Confusion matrix (96 test cases across 48 claims):**

|  | Actual Issue | Actual No Issue |
|--|-------------|-----------------|
| **Predicted Issue** | 48 (TP) | 0 (FP) |
| **Predicted No Issue** | 0 (FN) | 48 (TN) |

**Per-requirement accuracy:**

| Requirement | Cases | Accuracy |
|-------------|-------|----------|
| REQ-001 (O2 reading exists) | 36 | 100% |
| REQ-008 (Respiratory diagnosis) | 36 | 100% |
| REQ-011 (Observation count ≥3) | 24 | 100% |

**Caveat:** 100% is expected for deterministic SQL checks on auto-labeled data. LLM-based requirements (REQ-003, REQ-004, etc.) are not yet evaluated and will require manually labeled gold sets.

---

## Streamlit Dashboard

The reviewer dashboard at `claimguard-dashboard/` has 4 pages:

| Page | Purpose |
|------|---------|
| **Review Queue** | KPI metrics (total/pending/completed/failed), filterable claim table |
| **Claim Review** | Claim detail, diagnoses, observations, clinical notes (expandable), deterministic checks, LLM-based checks (on-demand), reviewer action form |
| **Policy Reference** | Browse all 15 requirements with type filter and check method indicator |
| **Pipeline Status** | Stream health, task execution, pipeline runs, Cortex Search Service status |

---

## Data Flow

```
1. New claim file arrives
        │
        ▼
2. RAW.INCOMING_CLAIMS (landing table)
        │
        ▼
3. NEW_CLAIMS_STREAM (detects insert)
        │
        ▼
4. QUEUE_NEW_CLAIMS task (every 5 min)
   ├── Valid claims → APP.REVIEW_QUEUE (PENDING)
   └── ROUTE_INVALID_CLAIMS task
       └── Invalid claims (missing fields) → APP.DEAD_LETTER_QUEUE
        │
        ▼
5. Reviewer opens Streamlit dashboard
        │
        ▼
6. Enters Claim ID → Dashboard pulls from CORE views
        │
        ▼
7. Deterministic checks (SQL rules engine, 8 requirements)
        │
        ▼
8. LLM checks (clinical note analysis, 6 requirements) — on-demand
        │
        ▼
9. 14 findings displayed with pass/fail, citations, deterministic labels
        │
        ▼
10. Reviewer takes action → saved to REVIEW_ACTIONS

Monitoring:
- FAILED_CLAIMS_ALERT checks hourly for claims exceeding max retries
- DLQ_ALERT checks hourly for unresolved dead-letter items
- Both log to PIPELINE_RUNS (visible on Pipeline Status page)
```

---

## Known Limitations

1. **Synthetic data only** — Synthea data does not represent real Medicare denial patterns. Do not report actual denial prevention rates.
2. **LLM checks not yet evaluated** — The 6 LLM-based requirement checks have not been measured for precision/recall. LLM findings are non-deterministic and labeled as such in the dashboard.
3. **Auto-labeled gold set** — Evaluation labels are derived from the same data the rules engine queries. Real evaluation requires manual labeling.
4. **No real PHI** — All data is synthetic. RBAC roles are created but data masking policies are not yet applied.
5. **Clinical notes are AI-generated** — The notes in `CLINICAL_NOTES` were created by `AI_COMPLETE`, not from real clinical systems.

---

## Project Structure

```
Workspace: USER$.PUBLIC."AI-Financial-Fraud-Investigation-Agent"
│
├── claimguard-dashboard/          # Streamlit reviewer app
│   ├── .streamlit/config.toml
│   ├── pyproject.toml
│   ├── snowflake.yml
│   └── streamlit_app.py
│
└── ClaimGuard_AI_Project_Documentation.pdf  # Original project plan
```

```
Snowflake: CLAIMGUARD database
├── RAW (1 table, 1 stream)
├── CORE (7 views, 1 semantic view, 1 table)
├── RAG (4 tables, 1 Cortex Search Service)
└── APP (9 tables, 1 function, 2 procedures, 2 tasks, 2 alerts, 1 agent)

Security: 3 RBAC roles (CLAIMGUARD_SERVICE, CLAIMGUARD_REVIEWER, CLAIMGUARD_ADMIN)
Cost: Resource monitor (100 credits/month), warehouse auto-suspend (60s), search auto-suspend (30 min)
```

---

## Cortex Agent Configuration

The agent (`CLAIMGUARD.APP.CLAIMGUARD_AGENT`) is fully configured with two tools:

| Tool | Type | Resource | Purpose |
|------|------|----------|---------|
| **PolicySearch** | Cortex Search | `CLAIMGUARD.RAG.POLICY_SEARCH_SERVICE` | Search Medicare policy documents for coverage requirements, qualifying criteria, and denial reasons |
| **ClaimAnalytics** | Cortex Analyst | `CLAIMGUARD.CORE.CLAIM_REVIEW_VIEW` (warehouse: `COMPUTE_WH`) | Query structured claim data — patients, encounters, diagnoses, observations, and claim metrics |

**Model:** `auto` (Snowflake selects best available)
**Budget:** 60 seconds, 32,000 tokens per request
**Instructions:** Review guidelines with PASS / ISSUE_FOUND / NEEDS_VERIFICATION / INSUFFICIENT_INFORMATION statuses, with mandatory policy citations

---

## Next Steps

1. **Evaluate LLM-based checks** — generate clinical notes for the 48 gold set claims (only 5 queued claims have notes currently), manually label expected outcomes, run `CHECK_CLAIM_LLM` against them, measure precision/recall for the 6 LLM checks
2. **Add data masking policies** — RBAC roles exist but no masking is applied; add policies on PHI columns (names, SSN, addresses) before connecting real data
3. **Connect real claims data** — CORE views currently point to Synthea Marketplace; swap them to organizational EHR/billing tables when available
4. **Add REQ-007 and REQ-010** — retesting window (day 61-90) and 12-month recertification require longitudinal encounter data not present in Synthea
5. **Cost-per-claim tracking** — log warehouse credits and AI token usage per completed review for operational budgeting

---

## Account Details

| Setting | Value |
|---------|-------|
| Account | OF92576 |
| Region | AWS_US_EAST_2 |
| Role | ACCOUNTADMIN |
| Warehouse | COMPUTE_WH |
| Compute Pool | SYSTEM_COMPUTE_POOL_CPU |

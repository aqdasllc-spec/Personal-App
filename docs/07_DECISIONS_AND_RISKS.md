# 07 — Decisions Needing Your Approval & Risk Register

## Decisions (recommendation first)
| ID | Decision | Recommendation | Alternative / trade-off |
|---|---|---|---|
| D-1 | Phase order | Phase 0 spikes, then **Tracker Engine before Library** | Keep your original order (Library first); riskier for sync/schema |
| D-2 | Sync | **Custom** field-level HLC sync on Supabase | PowerSync 2.6.1: less code, extra service/cost, different conflict semantics |
| D-3 | PDF engine | **pdfrx (PDFium, MIT)** + own annotation layer, pending S-1/S-2 | Syncfusion viewer (commercial/Community licence; native text-markup annotations only documented); commercial SDK |
| D-4 | Tracker storage | **Cells-as-rows** + typed value columns; formulas/rollups computed locally, never synced | JSON-per-record (simpler, worse conflicts/indexing) |
| D-5 | State/routing/DB | Riverpod 3 · go_router · Drift | — |
| D-6 | OCR | Evaluate in S-5; likely ML Kit (mobile) + OS OCR/Tesseract (desktop) | Defer OCR to a later release |
| D-7 | Rich-text editor | flutter_quill vs. custom Markdown editor — decide after spike in Phase 5 | — |
| D-8 | Encryption scope | SQLCipher DB + encrypted backups; **no E2EE cloud in v1** | E2EE: strongest privacy, but disables server scan/AI/search on cloud copies |
| D-9 | Multi-user | Single-user v1, schema ready for sharing | Add sharing/collab in v1 (large scope increase) |
| D-10 | Formats beyond PDF | PDF only in v1; EPUB/DOCX as P6+ (needs separate reader/converter) | Include EPUB in v1 |
| D-11 | App name/brand | "Folio" placeholder | Your choice |
| D-12 | Account model | Optional account; local-only mode supported | Account mandatory |
| D-13 | Minimum OS | Win 10+, macOS 12+, Android 8+/10+, iOS 15+ (pdfrx requires iOS 15 / macOS 12) | Higher floor for less testing |

## Risks
| ID | Risk | Likelihood / Impact | Mitigation |
|---|---|---|---|
| R-1 | True PDF annotation export not feasible on every platform | **Low-Med** (verified on Linux; others pending) / High | Spike S-2 done on Linux; flatten fallback; `PdfEngine` abstraction; Syncfusion fallback |
| R-2 | SQLCipher/sqlite3mc on `sqlite3` 3.x hooks across 4 platforms | **Low-Med** (verified on Linux; documented for all) / Med | Spike S-3 done on Linux; fallback OS-level protection + encrypted blobs/backups |
| R-3 | Cells-as-rows performance at scale | **Low** at 10k (S-7 passed); Med at 100k unfiltered aggregates / Med | Cached per-view aggregates; device benchmarks in Phase 2 |
| R-4 | Sync correctness bugs → data loss | Med / Very high | Property-based convergence tests; conflict log; soft deletes; independent backups |
| R-5 | Flutter/package churn (Flutter ≥3.47, Riverpod 3, sqlite3 3 hooks are recent) | Med / Med | Pin versions, lockfile, upgrade windows each phase |
| R-6 | Desktop notifications when app closed, Android exact alarms | Med / Med | S-6; document limitations honestly |
| R-7 | Scope size (this is a multi-team product) | High / High | Strict phase exits; ship vertical slices; defer AI/OCR/graph polish |
| R-8 | Windows build requires Developer Mode (pdfrx note) | Certain / Low | Document in dev setup; CI image preconfigured |
| R-9 | Cannot verify on real devices in this planning environment | Certain / Med | All platform claims are "documented, unverified" until the validation matrix is ticked |
| R-10 | Store policy (Apple sign-in rule, privacy labels, AI disclosures) | Med / Med | Release checklist; privacy review in Phase 7 |
| R-11 | Realistic bookshelf performance with many books | Med / Low | Lazy build, cached spine bitmaps, reduce-motion + grid fallback |

## Decisions status
All D-1…D-13 approved as recommended (user: "Approved", 2026-11-06). D-11 (name) remains the placeholder "Folio".

## Honest status
Phase 0 started: spikes S-1…S-4 and S-7 ran on Linux (`spikes/RESULTS.md`); S-5, S-6 and all non-Linux checks are outstanding. No product code yet. Package versions/capabilities were taken from pub.dev metadata and READMEs on 2026-11-06, not from running code. The HTML concepts in `/design` are static prototypes with illustrative sample content, **not** application functionality.

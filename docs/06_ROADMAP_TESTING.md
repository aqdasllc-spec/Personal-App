# 06 — Roadmap & Testing

## 1. Recommended phases
I recommend **two changes** to your order (justified by dependencies; your call, D-1):
- Add **Phase 0 — Validation spikes** *before* any product code, because several promised features (annotation export, DB encryption, desktop OCR, notifications on desktop) are unverified.
- Build the **Tracker Engine before the Library** (swap your Phases 2↔3): sync, search, goals, planner and dashboard all depend on it, and its data model is the highest-risk architecture decision. The library/reader is largely independent and can run in parallel if a second contributor exists.

| Phase | Scope | Exit criteria (all must be true) |
|---|---|---|
| **0 Spikes** (1–2 wks) | S-1…S-6 below, throwaway code in `/spikes` | Written result per spike, doc 04 updated, go/no-go on PDF engine, SQLCipher, OCR |
| **1 Foundation** | Repo/CI, design system + tokens, adaptive shell, Drift DB + migrations, Auth, Supabase schema + RLS + tests, secure storage, app lock, sync skeleton (outbox/pull/push for one table) | App runs on 4 platforms, login works, a test row round-trips between 2 devices offline→online, CI green |
| **2 Tracker Engine** | Schema, property types (basic → advanced), inline table editing, filters/sorts/groups, saved views, Kanban/List, relations, rollups, formulas, templates, CSV import/export, undo/redo, archive | 10k-record benchmark meets budget; property-based tests for formula & filters; field-level sync + conflict log working for trackers |
| **3 Goals, Projects, Planner** | Built-in templates, goal/project detail pages, progress rollups, Calendar/Timeline/Gantt/Gallery views, planner views, recurrence, reminders/notifications | Creating goal→project→task→milestone updates progress automatically; reminders fire on all 4 platforms |
| **4 Digital Library & Reader** | Import, content-addressed store, covers, shelves (3 views), metadata, PDF reader (render, thumbnails, TOC, search, tabs, zoom, fullscreen), annotations, bookmarks, progress, history, export (per S-2) | 500 MB PDF opens < 2 s; annotation round-trip across devices; export verified in Acrobat, Preview, Edge, Chrome |
| **5 Knowledge & Dashboard** | Notes, journals, daily notes, templates, backlinks, graph, global search (FTS), customizable dashboard | Search < 150 ms at 100k pages; widgets add/remove/resize/persist |
| **6 Advanced** | OCR, optional AI (consent flows), semantic search, analytics, backup/restore improvements (verify, test-restore, cloud) | Consent flow audited; backup restore tested from every prior format version |
| **7 Production readiness** | Cross-platform QA, security review (MASVS pass), perf tuning, accessibility, store assets, release | Release checklist (§7) complete |

*Note:* the three backup mechanisms' basic local version ships in Phase 1–2 (needed before real data lives in the app); improvements land in Phase 6.

## 1b. Phase 1 status (updated 2026-11-06)
**Done and verified here (Linux, headless):**
- Flutter app scaffold for Windows/macOS/Android/iOS/Linux; feature-first layout; Riverpod + go_router.
- `packages/sync_engine`: HLC, field resolve rule, set merge, 3-way text merge, simulation; 21 tests incl. 3 000 random scenarios.
- Supabase sync core migration + 40+ SQL assertions (RLS isolation, validation, idempotency, collation, denied direct DML) on Postgres 16; **mutation-checked** (breaking the rule or RLS makes tests fail); differential test: Dart reference ≡ Postgres on 300 scenarios (4 307 conflicts).
- Local DB (Drift, encrypted via sqlite3mc), generic `SyncedStore` (atomic write + clock + outbox), `SyncService` (push/pull/conflicts, resumable, idempotent, backoff), in-memory + Supabase transports; migration-test scaffolding with schema snapshot v1.
- Design system tokens/theme (light+dark, contrast tests), adaptive shell (sidebar/rail/bottom bar), sign-in/sign-up (validation, plain-language errors, local-only mode), app lock, DB key service, sync status chip, Settings (account/sync/app lock only).
- 36 app tests (`flutter test`), `flutter analyze` clean.

**Not done / not verified (be explicit):**
- **Nothing has run on Windows, macOS, Android, iOS** or any real device; the app has not been launched with a GUI (`main.dart` is analysed, not executed). Linux desktop build not attempted (no GTK dev libs here).
- **`SupabaseSyncTransport` and `SupabaseAuthRepository` have never talked to a live Supabase project** (server SQL is tested on plain Postgres with a stubbed `auth.uid()`).
- `local_auth` / `flutter_secure_storage` behaviour on real devices (only fakes tested).
- **MFA (TOTP)** not implemented (Phase 1 only did email/password + local-only). OAuth/Apple sign-in not implemented.
- Fonts (Fraunces, Inter) not bundled yet — platform fallbacks are used.
- Storage buckets/policies, Edge Functions, backup (local backup was planned for early phases) not started.
- CI workflow written but **never executed** (no GitHub Actions runner here).
- Sync covers one entity (`trackers`) and scalar values; multi-value/rich-text field codecs (using `mergeSets`/`mergeText`) are wired in Phase 2.
- Realtime push (we poll every 60 s and on resume) and background sync on mobile OS schedulers not implemented.

## 2. Phase 0 spikes
| ID | Question | Pass criteria |
|---|---|---|
| S-1 | Does pdfrx render, search, TOC, thumbnails smoothly on Win/mac/Android/iOS with a 500 MB and a 3000-page PDF? | 60 fps scroll on mid-range phone; memory < 400 MB |
| S-2 | Can we write true PDF annotations (highlight/ink/note/free text) into a copy via PDFium FFI, and do they open correctly in Acrobat/Preview/Edge/Chrome? Else flatten fallback quality | At least highlight+ink+note editable in 3 of 4 viewers, else choose fallback/Syncfusion |
| S-3 | SQLCipher via `package:sqlite3` 3.x build hooks on all 4 platforms with Drift + FTS5 + isolate | DB opens encrypted, FTS5 works, CI builds |
| S-4 | Sync prototype: HLC + outbox + `apply_changes` RPC with two simulated devices, RLS cross-user test | Deterministic convergence in property test (10k random op sequences) |
| S-5 | OCR: ML Kit on mobile; Windows OCR / Vision / Tesseract on desktop on 20 sample scans | ≥ 95 % word accuracy English, runtime/size budget |
| S-6 | Local notifications (scheduled, recurring) incl. Windows/macOS behaviour when app closed; Android exact-alarm limits | Fires within 1 min on all 4 |
| S-7 | 10k × 20 cells-as-rows benchmark in SQLite (filter/sort/group, table scroll) | p95 query < 50 ms |

## 2b. Phase 0 results (2026-11-06, Linux only — full detail in `spikes/RESULTS.md`)
| Spike | Result |
|---|---|
| S-1 | Partial pass: PDFium render/text/search OK headless; widget, large files, other platforms untested |
| S-2 | Pass on Linux: real annotations written & read by pypdf + poppler; Acrobat/Preview/Edge/Chrome + other platforms untested |
| S-3 | Pass on Linux: sqlite3mc and sqlcipher both encrypt, FTS5 works, isolates work; other platforms + Drift untested |
| S-4 | Pass at model level (5 000 randomized runs); found and fixed a silent-overwrite bug; sets/text-merge/Postgres RPC untested |
| S-5 | Not started |
| S-6 | Not started (needs devices) |
| S-7 | Pass: 10k records p95 < 10 ms; 100k has slow unfiltered aggregates |

**Phase 0 is therefore not fully closed**: the remaining checks need real devices/OSes. Phase 1 can begin on Linux-verified foundations, with these checks added to the Phase 1 exit criteria and `docs/validation-matrix.md`.

## 3. Testing strategy
- **Unit:** domain, formula parser/evaluator, filter/sort engine, rollups, HLC & merge, CSV codecs. Target ≥ 90 % in `packages/*`, ≥ 70 % overall.
- **Property-based:** random formula ASTs (parse∘print identity, no crashes, bounded time); random concurrent op sequences converge and lose no data (every dropped value appears in `conflicts`).
- **Database:** Drift migration tests from every released schema; FTS consistency; integrity checks.
- **Cloud:** SQL/pgTAP tests of RLS (user A can never read/write user B rows/objects), Edge Function tests, quota tests.
- **Widget/golden:** design-system components in light/dark, 3 breakpoints, large text scale.
- **Integration (per platform, CI + device farm):** onboarding, import PDF, annotate, create tracker, offline edit → reconnect → sync, backup → restore.
- **Manual exploratory** each phase using a written checklist; bug triage before phase exit.
- **Accessibility:** screen readers (TalkBack, VoiceOver, Narrator), contrast ≥ 4.5:1, 48 dp targets, keyboard navigation for desktop, reduce-motion.

## 4. Performance testing
Seeded generators for 10k/100k records, 1 000 books, 100k PDF pages of text, 5 000 notes. Automated benchmarks in CI (regression threshold 15 %); Flutter DevTools timeline on a low-end Android reference device; battery profiling for sync/indexing (background work throttled, constrained to charging/Wi-Fi where the OS allows); memory ceilings for reader tabs (page cache eviction).

## 5. Backup & recovery testing
Automated: create → backup → wipe → restore → deep-compare DB/blob hashes; restore from archives of *all earlier format versions* (kept as fixtures); corrupt-archive and wrong-passphrase cases; interrupted restore leaves original intact; 1 GB library restore time. Scheduled (monthly, on real build): disaster-recovery drill from cloud backup on a clean device.

## 6. Cross-platform validation matrix
Rows = features; columns = Win 11 / macOS (Intel+Apple Silicon) / Android 10–15 (phone + tablet, low-end) / iOS 15+ (iPhone + iPad). A feature is "Done" only when every column it claims is ticked with a test reference. The matrix lives in `docs/validation-matrix.md` (created in Phase 1) and is the single source of truth for what we can promise.

## 7. Release checklist
Security review & MASVS walkthrough · RLS tests green · dependency/OSV scan clean · migrations tested from oldest supported · backup/restore drill · crash-free sessions ≥ 99.5 % in beta · performance budgets met · accessibility audit · privacy policy & data-safety forms (Play, App Store privacy labels) · Apple/Google/Microsoft signing & notarisation · licence audit (pdfrx MIT, PDFium BSD/Apache, fonts OFL) · store listings · rollback plan · support/contact flow.

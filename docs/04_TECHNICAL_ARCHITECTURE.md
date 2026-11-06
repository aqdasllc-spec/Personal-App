# 04 — Technical Architecture

> Package versions below were read from the pub.dev API on **2026-11-06**. "Verified" means documented in the package's official page/metadata. **Nothing has been built or run on any target platform yet** (the planning container is Linux with no Flutter SDK). Items marked ⚠ must pass a Phase 0 spike (doc 06) before we promise them.

## 1. Technology stack
| Concern | Choice | Version (pub.dev) | Why / status |
|---|---|---|---|
| Framework | Flutter + Dart | pdfrx needs Flutter ≥ 3.47 / Dart ≥ 3.13 | One codebase, 4 targets. Pin exact SDK in Phase 1 with `fvm`. |
| State | **Riverpod** | flutter_riverpod 3.4.3 | Compile-safe DI, async-first, easy to test with overrides. |
| Routing | go_router | 18.1.3 | Deep links (`folio://note/<id>`), desktop multi-pane routes. |
| Local DB | **Drift** over SQLite | drift 2.35.3, sqlite3 3.9.0 | Typed queries, reactive streams, migrations with schema tests, FTS5. |
| SQLite binaries | `package:sqlite3` v3 (native-assets build hooks) | sqlite3 3.9.0 | **`sqlite3_flutter_libs` and `sqlcipher_flutter_libs` are now EOL ("0.x+eol… update to package:sqlite3 3.x")**, so we must NOT depend on them. |
| DB encryption | SQLCipher via sqlite3 3.x ⚠ | — | The EOL notice implies SQLCipher is reachable through sqlite3 3.x hooks, but I did not verify the exact config on all 4 platforms. Fallback: rely on OS file protection + app-level encryption of attachments/backups, and a DB-key in secure storage (see 05). |
| Cloud | Supabase (Postgres, Auth, Storage, Edge Functions) | supabase_flutter 2.18.3 | Requested. Android/iOS/macOS/Windows listed as supported platforms. |
| PDF | **pdfrx** (PDFium) | pdfrx 2.12.0 (MIT), pdfrx_engine 0.9.1 | See §6. |
| Secure storage | flutter_secure_storage | 11.2.0 | Keychain / Keystore / Windows DPAPI-credential store. |
| Biometrics | local_auth | 3.0.2 | Windows Hello, Touch/Face ID, Android biometrics. |
| Notifications | flutter_local_notifications + timezone | 22.3.3 / 0.11.2 | Scheduled local notifications on all four; desktop behaviour ⚠ test. |
| Rich text | flutter_quill (Delta ↔ Markdown) | 11.6.0 | Candidate; spike vs. a custom Markdown editor. `super_editor` last released 2024-06 → not chosen. |
| Charts | fl_chart | 1.3.0 | Dashboards. |
| Big table | two_dimensional_scrollables (`TableView`) | 0.5.6 | Official Flutter team package: virtualised 2-D scrolling for the spreadsheet view. |
| Graph | custom `CustomPainter` + force layout in isolate | — | `graphview` 1.5.1 (last release 2025-10) considered; decision at Phase 5. |
| OCR | ML Kit text recognition (mobile) ⚠; desktop: Windows OCR / Apple Vision via platform channels, or bundled Tesseract | google_mlkit_text_recognition 1.0.0 | **ML Kit is mobile-only** — desktop OCR is an open decision (D-6). |
| Crypto | `cryptography` (AES-GCM, Argon2id, HKDF) | 2.9.0 | Backup/export encryption; avoid the stale `encrypt` pkg (last release 2023). |

Official sources: [Flutter](https://docs.flutter.dev/) · [Riverpod](https://riverpod.dev/) · [Drift](https://drift.simonbinder.eu/) · [package:sqlite3](https://pub.dev/packages/sqlite3) · [pdfrx](https://pub.dev/packages/pdfrx) · [Supabase Auth MFA](https://supabase.com/docs/guides/auth/auth-mfa) · [Supabase RLS](https://supabase.com/docs/guides/database/postgres/row-level-security) · [Storage resumable uploads](https://supabase.com/docs/guides/storage/uploads/resumable-uploads) · [Storage signed URLs](https://supabase.com/docs/guides/storage/serving/downloads) · [Edge Functions](https://supabase.com/docs/guides/functions) · [OWASP MASVS](https://mas.owasp.org/MASVS/) · [PowerSync](https://docs.powersync.com/) · [local_auth](https://pub.dev/packages/local_auth).

## 2. Architecture
Feature-first modules, each with four layers. Dependencies point inward only.

```
lib/
  app/                 # bootstrap, router, theme, shell (adaptive navigation)
  core/                # result types, errors, logging, ids (UUIDv7), HLC clock, isolates, l10n
  design_system/       # tokens, ThemeData, components (button, field, table cell, card, dialog…)
  data/
    local/             # Drift database, DAOs, migrations, FTS, blob store (files)
    remote/            # Supabase client wrappers, storage, edge-function clients
    sync/              # change log, outbox, pull/push, conflict engine, status
    security/          # key management, biometric lock, encryption helpers
  features/
    home/ library/ reader/ tracker/ goals/ knowledge/ planner/ search/
    backup/ settings/ auth/ ai/ notifications/
      domain/          # pure Dart entities, value objects, repository interfaces, use cases
      application/     # Riverpod notifiers/controllers, orchestration
      data/            # repository implementations
      presentation/    # widgets, pages
packages/              # extracted pure-Dart packages (testable without Flutter)
  tracker_engine/      # schema model, cell codecs, filter/sort/group, formula parser+evaluator, rollups
  sync_engine/         # HLC, merge rules, conflict model
  fts_text/            # tokenisation helpers
```
`packages/tracker_engine` and `sync_engine` are pure Dart so they get fast unit/property tests and can be reused by an Edge Function (Deno) port if server-side validation is ever needed.

### Adaptive navigation
`NavigationShell` reads window size: expanded → sidebar + optional detail pane; medium → rail; compact → bottom bar (5 tabs + "More" for Settings) with a quick-capture button.

## 3. Local database (SQLite via Drift)
Conventions for **every syncable table**: `id TEXT PK` (UUIDv7, client-generated), `owner_id`, `created_at`, `updated_at`, `deleted_at` (soft delete), `hlc` (hybrid logical clock of last change), `dirty INTEGER` (local-only, not synced). Ordering uses **fractional indexing** strings (`sort_key`) so reordering touches one row.

### 3.1 Tracker Engine schema (the heart)
**Decision: sparse "cells-as-rows" with typed value columns, plus JSON for complex values.** Rationale below.

```
trackers        (id, name, icon, color, description, kind, template_id, archived_at, …sync cols)
properties      (id, tracker_id, name, type, config_json, sort_key, is_title, width, hidden_default, …sync)
records         (id, tracker_id, parent_id NULL, sort_key, archived_at, created_by, …sync)
cells           (record_id, property_id, v_text, v_num, v_int, v_json, hlc, PRIMARY KEY(record_id, property_id))
record_links    (id, relation_property_id, from_record_id, to_record_id, sort_key, …sync)
views           (id, tracker_id, name, layout, config_json, sort_key, …sync)
attachments     (id, owner_type, owner_id, property_id NULL, file_name, mime, size, sha256, local_path, remote_path, upload_state, …sync)
comments        (id, record_id, body_md, …sync)
reminders       (id, record_id NULL, property_id NULL, fire_at, rrule, …sync)
tracker_templates (id, name, payload_json, builtin)         -- data, not code
```
`properties.type` ∈ text, rich_text, number, currency, percent, checkbox, date, date_range, url, email, phone, select, multi_select, status, progress, person, files, image, relation, rollup, formula, created_time, last_edited_time.
`config_json` is typed per property type by a Dart sealed class (`PropertyConfig`) — e.g. select options `[{id,label,color}]` (cells store option **ids**, so renames/recolours don't rewrite cells), number format, currency code, formula source, rollup `{relationPropertyId, targetPropertyId, aggregate}`, relation `{targetTrackerId, reciprocalPropertyId?}`.

**Cell storage by type**
| Type | Column(s) |
|---|---|
| text, url, email, phone, select(id), status(id) | `v_text` |
| number, currency, percent, progress | `v_num` (REAL); currency stored as integer minor units in `v_int` to avoid float error |
| checkbox | `v_int` 0/1 |
| date | `v_text` ISO-8601 (`2026-11-06` or full UTC) + sortable `v_num` epoch |
| date_range | `v_json {start,end}` + `v_num`=start epoch for sorting |
| multi_select, person, files, image, rich_text (Delta/MD) | `v_json` |
| relation | **not in cells** — rows in `record_links` |
| rollup, formula, created_time, last_edited_time | **not stored/synced** — computed (see §3.3) |

**Why cells-as-rows (not one JSON blob per record, not a table per tracker):**
- *Per-field sync and conflicts.* Two devices editing different cells of one row merge cleanly; only the same cell conflicts (§7). A single JSON blob per record would force row-level conflicts.
- *Indexable filter/sort/group in SQL.* `CREATE INDEX cells_prop_num ON cells(property_id, v_num)` and `…(property_id, v_text)` make filtering a 10 000-row tracker an index range scan, not a Dart loop.
- *No DDL at runtime.* Adding a property is an `INSERT`, which is safe for migrations, sync and Postgres (no per-user table creation).
- *Cost:* a record read needs N cell rows (mitigated by one query `WHERE record_id IN (page)` and an in-memory cache keyed by record). Table view loads only visible columns × visible rows. A hot-path benchmark (10k records × 20 props) is a Phase 3 exit criterion.
- *Rejected:* table-per-tracker (runtime DDL, sync complexity), pure JSON1 expression indexes (index per user property is impractical).

**Postgres mirror (Supabase):** identical tables, `cells.v_json` as `jsonb`, `uuid` ids, RLS `owner_id = auth.uid()` on every table, composite indexes the same as local. A `change_log`-driven pull API (see §7).

### 3.2 Relations
A relation property points at another tracker. Edges live in `record_links`. A **two-way relation** creates a hidden reciprocal property on the target; both properties share a `pair_id` in config, and creating/removing a link writes the single edge once (reciprocal is a view of the same edge, queried by `to_record_id`). Deleting a record soft-deletes its edges; purging removes them. Cardinality (one/many) is validated in the use case, not the DB.

### 3.3 Formulas and rollups
- **Formula:** our own small expression language (Pratt parser in `tracker_engine`): literals, `prop("Name")`, arithmetic, comparison, `if`, `and/or/not`, text (`concat, length, upper, lower, contains, replace`), math (`round, floor, ceil, abs, min, max`), date (`now, today, dateAdd, dateBetween, formatDate`), list (`sum, avg, count, join`). Properties are referenced by **property id** internally (renaming is safe); the UI shows names.
- **Dependency graph** per tracker, topologically ordered; **cycle detection at save time** with a clear error.
- **Computed on read, memoised** in a per-session cache and persisted in a local-only table `computed_cache(record_id, property_id, value, input_hash)` for fast startup/sort. **Never synced** — each device derives the same value from synced inputs, which removes a whole class of conflicts. Because formulas are sorted/filtered on, the cache is indexed.
- **Rollup:** `aggregate(relation → target property)`: count, count_unique, sum, avg, min, max, median, percent_checked, percent_complete, earliest, latest, show_original. Invalidated via record_links / target cell changes.
- **Progress:** auto-progress for goals/projects = a rollup (`percent_checked` of subtasks, or weighted `avg` of child progress) — a built-in template wiring, not special code.

### 3.4 Nested records, subtasks, milestones
`records.parent_id` gives a tree inside one tracker (subtasks). Milestones are a normal property (checkbox "is milestone", or status) plus a view filter; no special table.

### 3.5 Views
`views.config_json` (typed, versioned): `{layout, filters: FilterGroup(and/or, nested), sorts[], groupBy{propertyId, sortOrder, hideEmpty}, visibleProperties[], propertyWidths{}, frozenColumns, rowHeight, kanban{groupPropertyId, cardProperties}, calendar{datePropertyId}, timeline/gantt{startPropertyId,endPropertyId,dependencyRelationId?}, gallery{coverPropertyId,size}}`. Views hold **no records** — they are queries — so switching views cannot duplicate or fragment data. Filter operators are typed by property type (e.g. text: contains/is/starts with/is empty; number: =,≠,<,>,between; date: is, before, after, in last/next N days, is relative today…).

### 3.6 Other domains (all on the same conventions)
- **Library:** `documents` (title, authors json, language, file hash, page_count, cover_path, added_at, last_opened_at, progress_page, progress_ratio, favorite), `shelves`, `shelf_items(shelf_id, document_id, sort_key)`, `document_tags`, `reading_sessions`, `bookmarks`, `annotations`, `doc_text_pages(document_id, page, text)` + FTS.
- **Annotations:** `annotations(id, document_id, page, type[highlight|underline|strike|ink|note|text], color, geometry_json in PDF user-space points, text, created_at)` — non-destructive; see §6.
- **Knowledge:** `notes(id, title, body_md, kind[note|journal|daily], daily_date, …)`, `note_links(from_note_id, target_type, target_id, anchor)`, `tags`, `taggings(tag_id, entity_type, entity_id)`, `note_templates`.
- **Planner:** `tasks`, `events`, `time_blocks` are **a built-in tracker + calendar view** where possible (tasks are tracker records so they appear in Goals & Projects); `events`/`time_blocks` are lightweight tables with RRULE for recurrence.
- **Goals:** a built-in *template* of 3 linked trackers (Goals ⇄ Projects ⇄ Tasks) with rollup progress. Users can edit or ignore it. Dedicated goal/project detail pages are just a presentation of one record + its related records.
- **Dashboard:** `dashboard_layouts`, `dashboard_widgets(id, layout_id, type, config_json, x, y, w, h)`.
- **Infra:** `sync_outbox`, `sync_state`, `conflicts`, `audit_log` (local), `app_settings`.

### 3.7 Search
SQLite **FTS5** virtual tables (external-content, `unicode61 remove_diacritics`; `trigram` index for substring on titles): `search_index(entity_type, entity_id, title, body, tags)` populated by triggers/DAOs. PDF text is extracted page-by-page in a **background isolate** (pdfrx text API) into `doc_text_pages` and indexed, with progress and resumability; scanned pages with no text layer are queued for OCR (⚠ §9). Results are ranked with `bm25()` and grouped by entity type. Fully offline for local content. Tracker cell text is indexed from `v_text`/rich-text plain text only.

### 3.8 Migrations
Drift versioned migrations + generated schema snapshots committed to the repo; CI runs *every* historical schema → latest migration test with seeded data. Destructive migrations require a pre-migration automatic local backup (same format as §8 of doc 05).

## 4. Files and attachments
Content-addressed local store: `<appdata>/blobs/<sha256[0:2]>/<sha256>`; DB rows reference hash. De-duplicates imports, makes sync resumable and verification trivial. Remote key: `users/<uid>/blobs/<sha256>` in a **private** bucket. Original PDF files are never modified; annotations live in the DB (exports produce new files).

## 5. Performance design
Virtualised `TableView`/`SliverList`, keyset pagination (not OFFSET), `WHERE record_id IN (…)` batch cell loads, DB access on a background isolate (Drift isolate), PDF page rendering via pdfrx's cache with priority hints, thumbnails/covers generated once and cached on disk, all indexing/extraction/OCR/sync in isolates with cancel + resume. Budgets (to be measured in Phase 7, enforced earlier in CI benchmarks): cold start < 2 s mid-range Android; 10k-row table scroll at 60 fps; open 500 MB PDF to first page < 2 s; global search < 150 ms on 100k indexed pages.

## 6. PDF engine evaluation
| Option | Engine / licence | Platforms (listed) | Viewing | Text search/select | Annotations | Notes |
|---|---|---|---|---|---|---|
| **pdfrx 2.12.0** | PDFium, MIT | Android, iOS, Windows, macOS, Linux, Web | Yes, fast, tiled | Page text API available (search helper exists) | **Not advertised as an annotation editor.** Provides custom page overlays, so we can draw our own layer. | Active (published 2026-11-05). Needs Flutter ≥3.47, Windows Developer Mode for build, small C toolchain. |
| syncfusion_flutter_pdfviewer 35.1.43 | Syncfusion, **commercial** (Community licence for qualifying devs) | Android, iOS, web, Windows, macOS, Linux | Yes | Yes | **Text-markup annotations (add/remove/modify) documented**; freehand/sticky/text not stated in its README | Licence terms must be accepted; closed source; larger lock-in. |
| pdfx 2.11.0 | PDFium wrappers | — | basic | limited | none | Less capable than pdfrx. |
| flutter_pdfview / pdf_render | native views / old (pdf_render last 2024-08) | partial | basic | — | none | Rejected: not 4-platform / unmaintained. |
| `pdf` + `printing` | Dart PDF *generation* | all | not a reader | — | can't edit existing pages | Useful only for flattened export fallback. |
| Apryse/PSPDFKit-class SDKs | commercial | native SDKs, Flutter wrappers vary | full | full | full | Costly; evaluate only if spikes fail. |

**Recommendation (pending spike S-1/S-2):** **pdfrx** for rendering, text, search, outline, thumbnails, with **our own annotation layer**:
- Selection → quad-points in PDF user space → stored in `annotations`; drawn as an overlay in the viewer's page-overlay hook; ink stored as simplified strokes (Douglas-Peucker + pressure), sticky notes as anchored pins. This is non-destructive, instantly syncable, searchable and works identically on all platforms.
- **Export annotated PDF** ⚠: preferred path writes *real* PDF annotation objects through PDFium's annotation API (FPDFPage_CreateAnnot…) via FFI on top of pdfium_dart — **I have not verified that these bindings are exposed or work on all four platforms**. Fallback (guaranteed): vector-flatten overlay into a copy using PDF content-stream append, or raster-flatten pages with `pdf`. Spike S-2 decides; the UI will say "export with editable annotations" only if S-2 passes.
- Syncfusion remains the fallback if S-1/S-2 fail; the annotation *model* is engine-agnostic (`AnnotationRepository`), and the reader sits behind a `PdfEngine` interface so the swap is contained.

## 7. Offline-first sync
### 7.1 Model
Local DB is the source of truth for the UI. Every mutation (in one transaction): writes the row(s), bumps `hlc`, appends to `sync_outbox(entity, id, op, changed_fields, hlc, base_hlc)`.
- **HLC** (hybrid logical clock: wall time + counter + device id) gives a total order across devices without trusting wall clocks; clock-skew > 24 h is flagged.
- **Push:** batches of outbox entries → Postgres RPC `apply_changes(batch)` (idempotent by `(device_id, change_id)`). Server stores each accepted change into `change_log(seq bigserial, …)`.
- **Pull:** devices request `change_log WHERE seq > last_seq`; cursors persisted in `sync_state`. Optional Supabase Realtime pings "new seq available" to avoid polling; polling at app resume + 60 s is the baseline.
- **Retry:** exponential backoff with jitter, per-batch; poison changes are parked in `sync_outbox.failed` and surfaced in UI — never dropped.
- **Files:** Supabase Storage **TUS resumable uploads** for files (6 MB chunks; see docs), checked by sha256; downloads on demand ("available offline" toggle per book).

### 7.2 Conflict strategy (nothing is silently overwritten)
Granularity is **per cell / per field**.
1. Non-overlapping edits (different cells/fields) → merged automatically.
2. Same field edited on two devices since their common base (`base_hlc` ≠ server's current hlc) is a **conflict**:
   - *Scalar fields* (number, select, checkbox, date…): last-writer-wins by HLC **but the losing value is recorded** in `conflicts` (entity, field, losing value, both devices, times) and shown as a non-blocking "1 edit was replaced — Review" badge with one-tap restore.
   - *Long text / notes / rich text:* three-way merge on the common base (line/paragraph-level diff3). Clean merges apply; overlaps keep **both versions** as a conflict copy that the user resolves in a side-by-side view.
   - *Multi-valued (multi-select, files, relations):* set-union/remove-wins-by-tombstone merge (add-wins), recorded in the conflict log if an element was both removed and edited.
   - *Delete vs. edit:* the edit wins and un-deletes (soft delete), with a notice.
3. Ordering (`sort_key`) conflicts resolve by deterministic tie-break on id (fractional keys rarely collide).
4. Version history: last N (default 50) versions of each note body and record are kept locally and synced, enabling manual rollback.

### 7.3 Sync UI
Global status chip (Synced · Syncing n · Offline · Needs attention), last successful sync time, pending-change count, per-file upload progress, conflict inbox.

### 7.4 Alternative considered
**PowerSync 2.6.1** (SQLite ⇄ Postgres sync, officially integrates with Supabase) would remove most of §7 but adds a hosted/self-hosted service and its own conflict semantics (server-authoritative, custom upload logic). Decision D-2 for you: custom (default here; only Supabase, full control of the conflict log) vs. PowerSync (less code, extra infrastructure and cost).

## 8. Cloud architecture (Supabase)
- **Auth:** email+password and OAuth providers (Apple required on iOS if other social login is offered), email verification, **TOTP MFA** (Supabase Auth MFA), session refresh tokens stored in secure storage (not shared_preferences).
- **Postgres:** mirror schema, RLS on every table (`owner_id = (select auth.uid())`), `SECURITY INVOKER` functions, `apply_changes` RPC validating shapes/sizes, `change_log` + `audit_log` append-only tables, per-user quotas.
- **Storage:** private buckets `blobs`, `backups`; RLS policies on `storage.objects` by path prefix `users/<uid>/`; downloads through **signed URLs** (short TTL); upload size/MIME limits at bucket level plus validation in an Edge Function.
- **Edge Functions (Deno):** `scan-upload` (malware scan webhook), `delete-account` (cascading purge), `export-data`, `ai-proxy` (holds provider keys, enforces consent flag + rate limit; **keys never ship in the client**), `backup-prune`.
- **Config:** only the Supabase URL and the *anon* key ship in the app (public by design; RLS enforces access). The service-role key exists only in Edge Function secrets.

## 9. OCR (evaluation, not a promise)
Scanned PDFs: rasterise page (pdfrx) at ~300 dpi in an isolate → recognise → store text in `doc_text_pages` (flag `source='ocr'`). Mobile: ML Kit (on-device). Desktop: Windows.Media.Ocr / Apple Vision through platform channels, or bundled Tesseract (Apache-2.0, larger binary). Decision D-6 after spike S-5 on language quality and size. Always on-device — OCR content never leaves the machine unless AI is enabled and consented.

## 10. Optional AI
Module `features/ai` behind a single `AiGateway` interface; disabled by default; no network code path is reachable while disabled. Provider/model configurable; requests go through the `ai-proxy` Edge Function (or user-supplied key stored in secure storage and used client-side only if the user chooses "bring your own key", with an explicit warning). Details in doc 05 §7.

## 11. Testing hooks built into architecture
Pure-Dart `tracker_engine`/`sync_engine` (property-based tests), repository interfaces for fakes, `Clock`/`IdGenerator` injection, golden tests for design-system components, Drift schema-migration tests, integration tests per platform (doc 06).

## 12. Diagrams
See [`/architecture`](../architecture/README.md): system context, layers, ER diagram, tracker engine, sync flow, conflict flow.

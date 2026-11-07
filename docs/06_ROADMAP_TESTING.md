# 06 — Roadmap & Testing

## 1. Phases (revised 2026-11-06 after the scope change)
Sections: **Home, Library, Planner, Settings**. The tracker engine (old Phase 2) was built, tested and then **removed at the user's request**; its history is in git (`git log -- packages/tracker_engine`).

| Phase | Scope | Status |
|---|---|---|
| 0 Spikes | PDF, encrypted DB, sync model, schema benchmark | done on Linux (see §2b) |
| 1 Foundation | app shell, design system, encrypted DB, sync core (client + Supabase SQL), auth, app lock, settings, rotation | done and tested headless; **not yet run against live Supabase** |
| ~~2 Tracker Engine~~ | ~~custom trackers~~ | **removed** |
| **4 Planner — BUILT (2026-11-06), see §1d** | tasks, events, repeat, time blocks, reminders, Day/Week/Month/Year | built; **not yet tried on a real phone** |
| 3 Library & Reader | import PDFs, content-addressed store, covers, shelves (shelf/grid/list), PDF reader (render, thumbnails, outline, search, tabs), annotations, bookmarks, progress, export | next |
| 4 Planner | tasks (table exists), events, day/week/month/year views, recurrence, time blocks, reminders & notifications | after Library |
| 5 Home | dashboard widgets over tasks, deadlines, reading progress, recents; global search | after Planner |
| 6 Hardening | backup/restore (local, cloud, encrypted export), OCR, MFA, live Supabase testing, accessibility | — |
| 7 Release | cross-platform QA, security review, performance, store release | — |

*Order note:* the Planner is small compared with the PDF reader; if you want something useful on your phone sooner, Planner first is reasonable — say so.

## 1m. Planner sub-tasks (2026-11-07)
Tasks can have a checklist of **sub-tasks**: add/rename/tick/remove them in the task editor (the field at the bottom of the list adds on Enter or the arrow; a typed-but-unadded one still counts on Save); the task row shows a counter ("2/5") that expands the sub-tasks in place so they can be ticked without opening the editor. Completing a **repeating** task starts the next occurrence with all sub-tasks unticked (undo restores the ticks). Ticking every sub-task does **not** close the task. Storage: one synced JSON field `checklist` on `tasks` (DB v9) — no new server table, so **no Supabase change is needed**; a conflicting edit of the same checklist on two devices is last-writer-wins on the whole list (the loser is kept in the conflict log). Limits: 100 sub-tasks, 200 characters each. Backups include them (older backups restore fine). 202 headless tests. Not built: reordering sub-tasks, sub-tasks of sub-tasks, per-sub-task due dates.

## 1l. Highlights and notes (2026-11-07)
Select text in the reader -> the menu gains **Highlight**. Highlights are saved per line of text (page coordinates), painted over the page (multiply blend), and listed in the sheet behind the list icon (tabs Bookmarks | Highlights): tap = jump to the page, coloured dot = cycle yellow/green/blue/pink, note icon = add/edit a note, bin = remove. Included in backups; DB v8. Tested: line-merging, storage, list/note/colour/jump/delete, backup round trip (191 tests). **Unverified on a device:** selecting text with the real viewer, the menu item, and the painted overlay. Not built: tapping a highlight on the page to edit it, exporting annotated PDFs, drawing/pen annotations.

## 1k. PDF search + password-protected backups (2026-11-07)
**PDF search:** magnifier in the reader → type, match count "3 / 12", previous/next (wraps), matches highlighted on the page (pdfrx text search). Scanned PDFs have no text layer, so they report "No matches". Logic tested with a fake viewer; **real highlighting/jumping unverified on a device.**
**Backup password (optional):** asked when you tap Back up now ("No password" keeps the old plain zip). AES-256-GCM, key from PBKDF2-HMAC-SHA256 (150 000 iterations, random salt), 1 MiB chunks authenticated with position + final flag, so a wrong password, a changed byte, reordered chunks and truncation are all detected. Restoring asks for the password (wrong one -> asks again). No password recovery exists by design. Speed ~6 MB/s in a desktop debug run (20 MB in 3.5 s); a multi-GB library will take minutes — unverified on phones. Lint cleanup applied (`dart fix`).

## 1j. Round 3 (2026-11-07)
**Preview card** now opens centred on the screen (dimmed backdrop on long-press). **Cloud badge** is a rectangle across the top of each book (same width as the book, 21 px high): red "Sync", rotating arrows "Syncing", green "Synced"; icon only on very narrow spines. Bug found by tests and fixed: tapping the badge while syncing used to fall through and open the book. **Real first-page covers** in grid, list and Home tiles (rendered once, cached, at most 2 renders at a time). **Reader bookmarks**: bookmark the current page, list them, jump to a page, remove; included in backups. DB v7. 178 headless tests; on-device behaviour of jump-to-page unverified.

## 1i. Book preview card (2026-11-07)
Hover (mouse) or long-press (touch) a book on the shelf, grid, list or Home: a card floats above it with the **first page**, the **full title**, author and progress. Long-press adds Read / More buttons (More = the book menu). The first page is rendered once with PDFium and cached under `<library>/covers/`. Tested with a fake renderer; **the real first-page render is unverified on a device** (falls back to a coloured cover if it fails).

## 1h. Per-book cloud sync (2026-11-07)
**Built:** each book has a dot in its top-right corner — red = only on this device, rotating arrows = uploading, green = a copy is in the user's private cloud. Tap red → Sync/Cancel; tap green → Unsync/Cancel (Unsync deletes the cloud copy; the book stays on the phone). Removing a synced book also deletes its cloud copy (if the cloud is unreachable the book stays). Books that exist only in the cloud are offered via a Download banner (checksum-verified). Server: private storage bucket `books` + table `cloud_books`, both locked to the owner by RLS (`supabase/migrations/20261107000000_cloud_books.sql`, SQL-tested on Postgres 16).
**Verified:** 168 headless tests incl. dot states, dialogs, failures, sign-in requirement, download. Setup SQL ran successfully on the user's Supabase project.
**NOT verified:** a real upload/download against live Supabase Storage (the first one is the test), large files (free plan: 50 MB per file, 1 GB total), a second device.

## 1g. Backup & restore (2026-11-06)
**Built:** Settings → Backup: "Back up now" writes ONE `.folio` file (zip: manifest, data.json with SHA-256 check, every PDF) and opens the system share sheet (save to Files/Drive, send). "Restore from a file" validates the file (not a backup / damaged / tampered / made by a newer app are refused with a plain message), shows a summary, then **only adds what is missing — never deletes or overwrites**; PDFs are checksum-verified before they are accepted. Restored tasks/events go through the normal sync write path. Home nudges when there is data and no backup in 14 days.
**Verified (Linux, headless):** round trip to an empty device, idempotent restore, local edits survive, duplicate PDFs, tampering, damaged/missing PDFs, share dismissed = not recorded.
**NOT verified:** the real Android share sheet / Files save, very large libraries (zip is streamed to disk, but restore reads the entry index into memory), iOS/desktop. **Not built:** backup encryption (the file is plaintext — stated in the UI), automatic scheduled backups, restoring a *replace-all* snapshot, cloud backup.

## 1f. Home (2026-11-06)
**Built:** greeting + date, quick-add task for today, Today card (overdue, events, tasks with tick boxes, "N of M done"), Coming up (next 7 days), Continue reading (recent books, tap to resume). Tested headless (portrait, wide, landscape); not yet tried on a phone.

## 1e. Library status (2026-11-06) — first slice
**Built:** import PDFs (file picker, copied into the app's private folder, originals untouched, duplicate detection by SHA-256, unreadable files reported), shelf / grid / list views, search (title/author/file name), favourites, named shelves (create/rename/delete — books are kept), edit title/author, remove with Undo (purged on next start), reader (pdfrx/PDFium) that reopens on the last page and records recently-opened. DB v5 (local only; the library is **not synced** — PDF bytes are not uploaded).
**Verified:** repository + widget tests with a fake page counter / fake reader (147 tests green on Linux); the Android release APK builds and contains `libpdfium.so`.
**NOT verified:** the real PDF viewer on any device, large files, scroll performance. **Not built yet:** cover thumbnails (spines/tiles use a colour + initial), bookmarks, annotations, PDF text search, export, drag-to-shelf, library sync.

## 1d. Planner status (2026-11-06)
**Done and verified here (headless):** DB v4 with tested upgrade paths from v1/v2/v3; repeat rules (daily, weekly with weekdays, monthly with month-end clamping, yearly with 29 Feb, count/until) — tested in UTC, Berlin, New York, Auckland and Kolkata, including daylight-saving boundaries; day agenda (due/planned/all-day/overdue/midnight clipping), month/year counts, overlap layout, reminder selection (cap 60); repository with validation, diff-only writes and "completing a repeating task advances it"; two-device sync (merge of different fields, conflict log for the same field, delete/restore); UI: quick add, task/event editors, Day/Week/Month/Year views, undo, phone/landscape/desktop layouts; reminder planning with a fake scheduler (re-planned on change, not re-sent when unchanged).
**Built but NOT verified on a device:** real notifications. `LocalNotificationsScheduler` (Android/iOS/macOS) compiles and the APK contains the permissions/receivers, but I have not seen a notification fire. Scheduling is *inexact while idle*: Android may deliver a reminder a few minutes late when dozing (no special exact-alarm permission needed). Windows/Linux use a no-op scheduler (reminders saved, nothing fires) until set up there.
**Not done:** tapping a notification does not open the item (it just opens the app); editing a single occurrence of a repeating event/task (rules apply to the whole series); events with colours (stored, no picker); drag-to-reschedule and drag-to-resize time blocks; week start day is fixed to Monday; 12/24-hour follows 24 h; the Home dashboard does not yet show planner items; no search across tasks yet; all non-deleted tasks are loaded into memory (fine for personal use, revisit past ~10k).

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

## 1c. Phase 2 (Tracker Engine) — REMOVED 2026-11-06
*Historical: this was built and tested (tracker_engine 114 tests, 6,600-view SQL/reference differential, 31 UI tests) and then deleted at the user's request. Kept here only as a record.*
**Done and verified here (Linux, headless):**
- `packages/tracker_engine` (pure Dart, 114 tests): 23 property types (validate / parse / format / storage), formula language (parser, bounded evaluator, id↔name canonicalisation, cycle detection), filters/sorts/groups + view-config JSON, rollups across linked trackers (incl. goal→project→task progress chain), CSV parse/write/import-plan/export with injection guard, fractional indexing, 5 templates with id remapping.
- Drift schema v2 + tested v1→v2 migration with seeded data; sync of tracker data (cells, properties, records, links, views) incl. out-of-order arrival; conflict/merge behaviour tested between two devices.
- `TrackerRepository` (validated writes, ordering, two-way links, soft delete/archive/duplicate, views, templates) and a **SQL query translator verified by a differential test: 6,600 random views over 300 random trackers return identical rows in SQL and in the in-memory reference** (found and fixed two real bugs).
- UI (31 widget tests): virtualised grid with inline editing, keyboard navigation, multi-select + bulk edit, row/column menus, column resize, undo/redo, option/date/relation/multi-select pickers, property dialog (per-type settings, relation & rollup builders, live formula preview), view options (filters/sorts/group/columns), saved views, Board with drag between columns, List, record detail with subtasks, template picker, phone layout; 1,200-row virtualisation check.
**Not done (be explicit):**
- Calendar, Timeline, Gantt, Gallery layouts (planned Phase 3; offered as disabled "(Phase 3)").
- **Grouping is not rendered in the Table view** (group headers); it only drives the Board.
- CSV import/export has no screen yet (engine is done and tested; needs a file picker + dialog).
- Drag to reorder rows and columns (ordering is stored and tested; no drag UI yet), copy/paste of cell ranges, column summary row.
- People / Files / Images properties have **no editor UI** (types exist; attachments arrive with the Library/storage phase). Rich text is edited as plain text.
- Changing a property's type with data conversion, record comments, editing *nested* filter groups, "duplicate view".
- Performance: SQL path measured in-memory on a server CPU only; **nothing measured on a phone**. No GUI run: all UI behaviour is from widget tests, not from looking at a real screen.
- Undo/redo covers cell/row/property/link edits; not view changes; not persisted across restarts.

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

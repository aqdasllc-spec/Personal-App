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

## 1u. Welcome tour, month-view drag, Home order (2026-11-07)
**Welcome tour:** four screens (Welcome, Your library, Plan your days, Yours to keep) open once over Home on first launch; Skip or Get started marks it seen. **Settings -> Help:** reopen the tour and a cheat-sheet of gestures. **Month view:** on screens at least ~460 px tall a panel under the grid lists the picked day's tasks (arrows change the day); drag one onto any day cell to move it (time kept, Undo); tapping a cell still opens the day; short landscape screens have no panel (use the Week view). **Home -> Continue reading:** a menu switches between "Recently read first" and "My order" (the Library's own order, started books only); remembered. 296 headless tests. The tour copy is English only and unreviewed by a designer.

## 1t. Week view drag between days + arrow buttons (2026-11-07)
**Planner week view:** press-and-hold (touch) / drag (mouse) a task and drop it on another day: the date that falls on the day it was picked up moves (due date, planned time block, or both), the time of day stays, repeat rules and sub-tasks are kept; Undo is offered ("Moved to Sun 8"). Dropping on its own day does nothing; finished tasks are not draggable. The target day is tinted while hovering; on phones (days stacked) the list scrolls by itself near its edges. **Library rearrange mode:** tap a book to pick it (accent outline, tapping again puts it down) and use the **← →** buttons in the bar to move it one place earlier/later (disabled at the ends and while a search/filter is active); drag and drop still works. 286 headless tests. Unverified on a device: drag feel and auto-scroll speed. Not built: drag in the month view.

## 1s. Rearrange mode (pen button) (2026-11-07)
A pen button next to "New shelf" turns on **rearrange mode**: every book wiggles (not with the system's reduce-motion setting), tapping a book does nothing, and the preview card is off. **Drag a book onto another** to put it in that place (the others shift); the order is saved per book (DB v11 `sort_pos`) and the sort switches to the new **My order** option, which is remembered. While rearranging, all shelves are shown as drop targets: **drop a book on a shelf name** to move it there, on **All books** to take it off its shelf, on **Favourites** to star it. The list scrolls by itself when a dragged book is held near the top/bottom edge. With a search or filter active the order is locked (explained on screen) but shelf drops still work. Screen readers get "Move earlier / Move later" on each book. Works in shelf, grid and list views; 278 headless tests. Unverified on a device: the feel of the wiggle and drag. Side effect: the shelf-chip row is shorter on phones (one more button), so the last chips scroll.

## 1r. Recently removed (bin) (2026-11-07)
Removed books now stay in a bin for **30 days** (was: until the next app start): Settings -> Storage -> Recently removed -> Review lists them with "Removed N days ago · N days left", **Restore** (bookmarks, highlights, reading place and shelf are kept), **Delete for good** (confirmed) and **Empty bin** (confirmed). Adding the same PDF again while its copy is in the bin brings the original back instead of creating a duplicate. Startup deletes only books older than 30 days. Tested headless.

## 1q. Settings -> Storage (2026-11-07)
Shows what the library uses: books on this phone (count, size), cloud copies with a meter against the 1 GB free-plan figure (only in builds with cloud sync; your plan may differ), the first-page cover cache (**Clear**; rebuilt on demand), removed books waiting to be deleted (**Delete now**), and the 5 largest books. **Remove all cloud copies** (confirmed) frees cloud space and keeps every book on the phone; a partial failure reports how many succeeded. 262 headless tests. The meter uses the sizes recorded when books were added, not a live query of Supabase.

## 1p. Library: sort, status filter and tags (2026-11-07)
New **Sort and filter** button (badge = number of active filters) in the Library header: **sort** by recently added / recently read / title / author / longest (never-opened books and unknown authors go last; the choice and the view are remembered); **reading status** All / Not started / Reading / Finished (finished = 95 % of pages read); **tags** — free-form tags added in a book's Edit details (comma separated, cleaned up, max 20 of 30 characters), listed with counts, several can be combined (a book must have ALL of them). Active filters show as removable chips with an always-visible Clear filters; search also matches tags; the preview card shows the tags; tags are in backups (DB v10; local only, not in cloud metadata). 237 headless tests. Tag management: Sort and filter -> Tags -> **Manage** renames (renaming onto an existing tag MERGES them), or deletes a tag on every book at once (active filters follow). **Select several books** (checklist button): tap to pick, Select all (only the books shown), then Tag (add tags), Shelf (move), Favourite/Unfavourite; no preview card while selecting. **Remove** (confirm, Undo; a synced book's cloud copy is deleted first, and a book whose cloud copy can't be deleted is kept and reported) and **drag-select** (press and hold a book, slide over others; starting on a selected book deselects) were added later. Drag-select does not auto-scroll. Not built: tag colours, smart collections.

## 1o. Export highlights and notes (2026-11-07)
Reader -> list icon -> **Copy** / **Share** (shown once the book has a highlight or bookmark), and **Share notes** in the book menu. Produces one Markdown (.md) file per book: title, author, counts, then every highlight grouped by page (coloured marker, quoted text, your note), then the bookmarks. Opens in any text editor and pastes into Obsidian/Notion/Word/e-mail. Tested: exact output format, ordering, empty cases, safe file names, copy and share paths (217 tests). The real share sheet on a phone is unverified. Not built: exporting a PDF with the highlights drawn in.

## 1n. Drag a task onto the day timeline (2026-11-07)
In the Day view, press-and-hold a task (touch) or drag it (mouse) and drop it on the schedule: it gets a time block at the drop position, snapped to 15 minutes, keeping its length (default 1 h). A line with the drop time follows the pointer. Existing task blocks can be dragged to move them. Undo is offered ("Scheduled for 14:30"). Done tasks and events are not draggable. The schedule grid now also shows on days with open tasks but nothing timed, so there is somewhere to drop. Tested on a wide layout (4 tests). **Phone:** the list now scrolls by itself while a dragged task is held near the top/bottom edge, so a long list can reach the schedule; and every open task has a clock button ("Pick a time") that opens a time picker (starts at 09:00 or at the task's current time) — the quickest way without dragging. Both tested headless; the feel of the auto-scroll speed is unverified on a device.

## 1m. Planner sub-tasks (2026-11-07)
Tasks can have a checklist of **sub-tasks**: add/rename/tick/remove them in the task editor (the field at the bottom of the list adds on Enter or the arrow; a typed-but-unadded one still counts on Save); the task row shows a counter ("2/5") that expands the sub-tasks in place so they can be ticked without opening the editor. Completing a **repeating** task starts the next occurrence with all sub-tasks unticked (undo restores the ticks). Ticking every sub-task does **not** close the task. Storage: one synced JSON field `checklist` on `tasks` (DB v9) — no new server table, so **no Supabase change is needed**; a conflicting edit of the same checklist on two devices is last-writer-wins on the whole list (the loser is kept in the conflict log). Limits: 100 sub-tasks, 200 characters each. Backups include them (older backups restore fine). 202 headless tests. Reordering: drag a sub-task by its handle in the editor (screen readers get move up/down actions). Not built: sub-tasks of sub-tasks, per-sub-task due dates.

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

## 1v. Reader modes, scanned PDFs, app-icon shortcuts, accessibility audit (2026-11-07)

**Reader (Kindle-style):** the **Aa** button opens reading settings: colour scheme (Original, Paper, Sepia, Night, Black), Dim, Warm light, scroll direction (up/down or sideways page by page), tap-the-edge-to-turn-pages, keep screen on, orientation lock (auto / portrait / landscape). Tap the middle of the page to hide the bars; a slider at the bottom jumps through the book. Remembered; the phone's own orientation and screen-on settings are restored when you leave. Tested headless with fakes (10 tests).

**Scanned / handwritten PDFs:** on first open Folio checks whether the book has real text (PDFium on up to 5 pages). If it looks scanned, a banner offers **Make searchable**: pages are drawn and read on the phone with Google ML Kit (offline, Latin script), one at a time, saved as they go (DB v12 `page_texts`), with progress, **Stop** and resume. Search then uses that text (count, next/previous with wrap-around, jumps and marks the line on the page). Any book: more menu -> *Make searchable*, *Text of this page* (copy), *Read the pages again*. Page text is included in backups. 18 headless tests with a fake recogniser. **Unverified on a device:** the real ML Kit reading, speed and battery on long books, the yellow marks on the page, themes/filters looking right, tap zones, sideways layout, wakelock, orientation lock. **Limits:** printed Latin text only; handwriting is often not recognised; Windows/macOS have no recogniser yet.

**App-icon shortcuts (Android/iOS):** Continue reading, Add a task (opens Home with the cursor in the quick-add box), Planner: today, Library. Tested with a fake shortcut port; the real long-press menu is unverified, and the shortcut icons use the plugin default.

**Accessibility audit (automated only):** Home, Library, Planner in light and dark at 2x text: no overflow, tap targets big enough, tap targets labelled. It found and we fixed overflows (sync chip, Home card header). Settings was fixed afterwards (the Account button moved under its text) and is in the audit too. Not done: contrast checks, TalkBack on a real phone.

**Guide:** `docs/APP_GUIDE.md` lists what is where.

## 1w. Settings at large text, tag colours, pen drawings (2026-11-07)

**Settings** no longer overflows at 2x text (the Account button moved under its text); Settings is in the accessibility audit now (Home, Library, Planner, Settings x light/dark).

**Tag colours:** Sort and filter -> Tags -> Manage -> the circle by a tag picks one of 8 colours (or none). A dot shows on the filter chips, active filter chips and the preview card; renaming a tag keeps its colour (merging: the target's colour wins). Stored as one setting (`tag_colors`, synced like other settings), **not** in backups yet. Tested headless.

**Pen drawings:** reader menu -> Draw with a pen. Colour (6), thickness (3), Undo, Clear page, Done. Strokes are saved per page as fractions of the page (DB v13 `page_ink`), so they stay in place at any zoom; included in backups; removed with the book. While the pen is on, pan/zoom are switched off so a drag draws. Tested headless: capture of a drag into a stroke, saving, undo/clear, reopening, backup-independent repository tests. **Unverified on a device:** the real drawing feel (latency, smoothness), whether the viewer really stops scrolling while drawing, and the painting over the real PDF. Not built: eraser for single strokes, palm rejection, stylus pressure, exporting drawings into a PDF, drawings in cloud sync.

## 1x. Eraser, saved views, reader toolbars, voice reader, backups (2026-11-07)

**Eraser:** in the pen bar; touching a stroke removes it (reach about 2.5 % of the page); Undo now restores any change (draw, erase, clear). **Backups** now include tag colours (this device's own colour for a tag wins on restore), pen drawings and recognised page text. Drawings, tag colours and saved views are **local only**: syncing them would need a new server table (a Supabase change), not built.

**Saved views (smart collections):** Sort and filter -> Saved views: *Save this view* stores status + tags + sort under a name (max 20, same name replaces); tapping the chip restores them; the x deletes; renaming/deleting a tag updates the views. Local setting (`smart_views`).

**Reader toolbars:** top bar is now title + page counter, Search, Aa, More; a bottom row has Contents, Bookmark, Draw, Listen (56 px tap targets, labelled); the pen and voice bars wrap onto two lines on narrow screens. Tested portrait, small landscape and 2x text.

**Voice reader (Listen):** flutter_tts (the phone's own voice, offline if the voice is installed). Reads from the current page, turns pages, skips blank pages (stops after 3 in a row with a hint), speed 0.75x-2x, follows when you jump to another page, stops when you leave. Long pages are split at sentence ends (phone voices refuse very long input). Scanned books use the recognised text. Tested headless with a fake voice. **Unverified on a device:** the real voice, whether Pause/Stop really cut the speech immediately, the speed scale on your phone, the language the voice speaks (it follows the phone's language, not the book's), and behaviour with the screen off (no media notification / lock-screen controls).

## 1y. Sync of drawings / tag colours / saved views, lock-screen controls, export with drawings (2026-11-08)

**Sync:** three new synced "tables" using the existing field-level engine: `tag_colors` (one row per tag), `smart_views` (one row per view) and `page_ink` (one row per book page). Local storage is unchanged (a setting each, and the `page_ink` table); small hooks write remote changes into it, and the Library lists reload after each sync. Things made before this version are queued once at the first sync (`extras_backfilled`). **Needs a Supabase change:** run `supabase/migrations/20261108000000_sync_more_tables.sql` (adds the three names to the allow-list inside `apply_changes`; the rest of the function is identical). Until it is run, a signed-in phone's sync would be refused for those changes. SQL tests pass on local Postgres 16 (`supabase/tests/30_sync_more_tables.sql`); `server_contract_test` now reads the newest migration. Drawings of a book that is not on the other device wait there unused. Conflicts: the same tag / view / page edited on two devices at once -> the later edit wins, the other is kept in the conflict log (like tasks). Drawings are synced per page, so drawing different pages on two devices merges, drawing the same page does not. Tested with two simulated devices; **not tested against the real Supabase project.**

**Lock-screen controls for Listen:** audio_service media foreground service (Play/Pause, Previous/Next page, Stop; keeps reading with the screen off). Android manifest gained the service, a media-button receiver and WAKE_LOCK / FOREGROUND_SERVICE(_MEDIA_PLAYBACK); MainActivity extends the plugin's fragment activity (local_auth still works). Tested with a fake. **Unverified on a device:** that the notification appears, that reading really survives screen-off and battery optimisation on your phone, Bluetooth/headset buttons, Android 13+ notification permission (the app already asks for it for reminders).

**Export with drawings:** more menu -> Export as PDF with my drawings: this page / pages with drawings / whole book (<= 60 pages). Each page is drawn by PDFium as a picture (1100 px wide) and your strokes are added as vector lines on top; shared through the OS share sheet. Pages become pictures, so text in the exported copy cannot be selected; the original is untouched. Tested with a fake page drawer (PDF structure, page count, skipping undrawable pages, dialog, sharing). **Unverified on a device:** the real rendering, file size and time on long books, and how the lines line up with the page.

## 1z. Pen bar and pinch-zoom fixes, highlighter, voice choice, highlight/bookmark sync (2026-11-08)

**Pen bar:** was two wrapped rows plus the slider and tool row (about a quarter of a phone screen). Now ONE 52 px row (style pop-up, eraser, undo, clear, Done) that replaces the slider and tool row while the pen is on; the page area is the same size or larger than with the normal bars (tested at 411x890 and 850x390). **Two-finger zoom while drawing:** the ink layer only listens to touches (no gesture contest), the viewer keeps pinch-zoom on and only one-finger panning is off; a second finger drops the half-made stroke. **Stylus wins over palm:** while a stylus is down finger touches are ignored. Tested with simulated touches. **Unverified on a device:** that the real viewer pinch-zooms while the layer is on top (it should, by design), the palm rejection on your phone, and the zoom + pan feel (with one-finger pan off, a two-finger drag that does not change the zoom may not pan: use a small pinch).

**Highlighter:** a second pen type (wide, 40 % see-through, multiply blend; exported as a see-through line in the PDF). Stored with the stroke (`h`), synced like any stroke.

**Voice choice:** the people icon in the Listen bar opens language + voice lists built from what the phone reports (flutter_tts getVoices), "Phone default", and a sample button. Remembered (`tts_voice`, this device only). Applied when reading starts and when changed. Not verified on a device: which voices your phone lists and whether switching takes effect immediately.

**Highlights and bookmarks now sync** (tables `highlights`: fields body/color/note/gone, and `bookmarks`: field mark; both per row, so a colour change on one device and a note on another both survive). Older ones are queued once at the first sync (`marks_backfilled`). **Needs a second Supabase change:** run `supabase/migrations/20261109000000_sync_marks.sql` (after 20261108000000). SQL tests pass locally; the Dart side is tested with two simulated devices.

## 2a. Eight more features (2026-11-08)

1. **Voice matches the book:** the language of the page is guessed from its letters (Hindi, Urdu, Arabic, Persian, Bengali, Tamil, Telugu, Gujarati, Punjabi, Russian, Chinese, Japanese, Korean) or common words (English, French, German, Spanish, Portuguese, Italian, Dutch) and an installed voice for it is chosen when reading starts; with none installed the bar says so and the default voice reads. Switch in the voice sheet. A guess, not a promise (Latin text with no clues is taken as English; Urdu vs Persian is told by a few letters).
2. **Stylus only** (pen pop-up, remembered): fingers scroll/zoom, only a stylus draws.
3. **Pages sheet:** grid of page pictures (PDFium, drawn as you scroll), opens at the current page, bookmark and pen marks, tap to jump. Tested with fake pictures; real thumbnails unverified (speed on long books).
4. **Reading statistics (DB v14, local, not in backups or sync):** `read_pages` (day, book, page) and `read_time` (seconds per day). A page counts after 4 s on it; time ticks every 15 s while the reader is open and the app is in front. Home card: today vs goal (default 10, setting `read_goal`), streak (alive until you miss a whole day), best streak, last 7 days, week time.
5. **Search across all books** (Library -> magnifier-list button): text of every non-scanned book is read through PDFium one page at a time (slow for big libraries: progress and Stop are shown; max 20 hits per book, 300 in all); scanned books use the recognised text (only after Make searchable). A hit opens the reader at that page with the in-book search already running. A one-letter query is explained instead of searched.
6. **All highlights** (second tab of the same screen): every highlight, colour filters with counts, copy, tap to open, **colour meanings** (long-press a colour; local setting `highlight_meanings`).
7. **Folder import:** folder button -> picker -> count -> confirm -> every PDF (recursive, hidden skipped, max 2000). **Unverified on Android:** whether the folder you pick can be read; on Android 11+ the system may only grant access to files you pick one by one, in which case Folio says so and you use Add PDFs.
8. **Look up:** Select text -> Look up -> Meaning / Translate open the browser with the text (sent to Google); Copy. Needs internet; nothing is built in offline.

**Finished 2026-11-08:** the full suite was red when this was left as work in progress (3 failures in `search_all_test`). Fixed: the test made three identical PDF files, which the library rightly treats as one book; a one-letter query said "Nothing found" instead of asking for two letters; the colour-meaning dialog disposed its text field while it was still closing (crash in debug builds). Android now declares the https browser query that Look up needs on Android 11+. `flutter analyze` clean, all tests pass.

## 2b. Shelf styles (2026-11-08)

Settings → Library → **Shelf style** (local setting `shelf_style`, default Classic):
- **Turning books:** a first tap on a spine turns the book to its cover (the real first page when it has been rendered, otherwise a coloured cover with title and author) and a card floats at the bottom with progress, Put back, More and Read/Continue; a second tap opens it. Selection mode and rearrange mode work as before.
- **Glass cabinets:** "Continue reading" strip plus a wall of closed cabinets (one per shelf, plus *Unsorted* = new filter `NoShelf`). Tapping a cabinet chooses that shelf; it grows in and the two glass doors swing open (Matrix4 perspective, 620 ms; a fade with Reduce motion). Two rows inside: the top row fills first; if the books need more than two widths they are split evenly and each row scrolls sideways. The phone's Back closes the cabinet (PopScope). Search, status/tag filters, Favourites and rearrange mode fall back to Turning books. The glass is a drawn tint with reflection streaks, not a live blur (cheap on low-end phones).
- Tests: `test/features/library/shelf_styles_test.dart` (through the real shell: setting, turning, wall → cabinet → back, Unsorted, search fallback, small landscape). **Unverified on a device:** how the door swing and book turn feel, frame rate on a cheap phone, and the look of the cabinet colours.
- The earlier `CabinetWallView` design study is the "Folio Shelf Concepts" artifact; other ideas listed there are not built.

## 2c. Cover carousel, spotlight search, ribbons and dust (2026-11-09)

- **Cover carousel** (4th shelf style, `cover_carousel.dart`): only the covers within 5 of the middle are built (fine for big libraries), sorted far-to-near so the middle one is on top; perspective + rotateY; a drawn reflection; drag with velocity, arrows, keyboard (left/right/Enter). Middle book: title, "n of N", progress, More, Read/Continue. Rearrange mode falls back to Turning books; search and filters narrow the carousel.
- **Spotlight search** (`shelf_spotlight`, on by default): Classic, Turning books and Glass cabinets (which shows open shelves while searching) keep every book that passes the other filters, grey out non-matches (opacity .25 + greyscale) and give matches a brass glow; the shelf scrolls to the row of the first match. Not during rearranging.
- **Ribbons and dust** (`shelf_ribbons`, on by default), drawn on every spine: ribbon length = reading progress (replaces the thin progress line), three gold bands at 95 %+, dust = (days since last opened, or added, - 45) / 640, up to 0.5, as a veil plus fixed specks per book.
- Tests: 6 more in `shelf_styles_test.dart` (spotlight on/off, ribbons/gold/dust on/off, carousel arrows/swipe/read, carousel on a small landscape phone). **Unverified on a device:** swipe feel and frame rate of the carousel with real cover pictures, and how the dust looks on real colours.
- **Carousel, bigger (build 5):** covers are sized from the space left under the Library header (about 200 x 300 on a 411 x 890 phone, was about 145 x 213) and capped at 62 % of the width; the details under the cover are compact (title, one line of author/progress, thin bar, buttons that wrap) and the "n of N" moved onto the stage. **Full screen** (button on the stage): bigger covers, backdrop tinted with the middle book's colour, richer details (progress, last read, favourite chips); Close/Back returns the index. Fixed on the way: the buttons row overflowed at narrow widths / large text (now a Wrap); setting the position while rebuilding notified listeners outside the carousel (now after the frame, and only when the book list changed).

## 2d. Quran corner on Home (2026-11-09, build 6)

**Texts (offline, bundled, verbatim):** `assets/quran/quran.json.gz` (Arabic Uthmani Hafs from the King Fahd Complex; English Saheeh International; Urdu Fateh Muhammad Jalandhry; surah names, juz and sajda positions) and `assets/quran/hadith.json.gz` (983 hadith of Sahih al-Bukhari in Arabic, English and Urdu). Built by `tool/quran/build_assets.py` from the open datasets fawazahmed0/quran-api and hadith-api; nothing typed by hand. Checks in the script and in `test/features/quran/quran_test.dart`: 114 surahs / 6236 ayahs in each language and aligned; 1:1 and 2:255 spot checks; Bukhari numbering identical in the three languages, and only hadith whose English narrator is named in the Urdu, that quote the Prophet, and whose Urdu saying can be located (the Urdu edition starts with the chain of narrators; the card shows the text from the Prophet's mention on, verbatim after "…"; the sheet shows all). Sahih Muslim was left out: its Urdu numbering does not line up.
**Fonts (OFL):** Amiri Quran (covers every character of the Hafs text, checked with fontTools), Noto Nastaliq Urdu (Urdu), Scheherazade New (hadith Arabic; also added to the app's font fallbacks so ﷺ and Arabic/Urdu letters in ordinary text always render).
**Home cabinet:** full width, about 220 px high on a 411 x 890 phone (grows with large text, no overflow at 2x; passes the tap-target/label audit). Left: arched glass niche with lamp and the Quran on a rehal (drawn in code); tap = lamp lights (750 ms), Quran opens. Right: Daily Ayah (one of ~110 curated, self-contained references, e.g. 94:5-6) / Daily Hadith, Urdu or English (setting `quran_daily_lang`), tap = full sheet.
**Reader:** surah list with forgiving search, juz list, continue; ayah list (scrollable_positioned_list) with Bismillah header (not 1 and 9), ayah-end marks with Arabic digits, sajda marks; translation mode (`quran_translation`), text size (`quran_text_scale`), last place (`quran_last_read`, saved as you scroll and by the bookmark button).
**Audio:** just_audio streaming https://cdn.islamic.network/quran/audio/{kbps}/{edition}/{ayah 1-6236}.mp3; 14 reciters + Urdu (Shamshad Ali Khan) and English (Ibrahim Walk) spoken translations, each edition checked to return MP3 for 8 ayahs across the Quran (1 ... 6236). Queue per ayah (optionally interleaved with the translation), current ayah highlighted and followed, prev/next/stop, lock-screen controls through the existing audio_service handler. **Unverified on a device:** real streaming (buffering on slow networks), screen-off playback on your phone, the lamp animation's smoothness. Not built: offline audio download, a mushaf (page) view, tafsir.

## 2e. Quran corner, round 1 of the suggestions (2026-11-10, build 7)

- **Prayer times:** adhan library (Karachi/Hanafi default, 11 methods), checked against an independent implementation of the formulas (Lahore and London, within a minute). Hijri: Umm al-Qura (hijri package), checked against another converter, ±2 days adjustment. Place: geolocator (coarse, asked only on tap) or typed. Reminders: own channel `prayer_times`, ids 0x7f000000+, a week ahead on Android (iOS: a day, 64-notification limit), exact when allowed; planner ids now stay below 0x7f000000 and the planner never cancels that range. Strip at the foot of the cabinet (cabinet now about 250 px).
- **Khatm:** page of every ayah (Madinah mushaf, 604) added to the data; plan = days + start page, linear schedule, today's portion (catch-up folded in), status, progress; advanced by the reading place (never backwards).
- **Hifz:** queue built from (ayah, repeat, round, translation, silence) entries; just_audio SilenceAudioSource for pauses; Next/Previous within the round; bar shows repeat/round; hide the Arabic.
- **Search:** Tanzil simple text without vowel marks added for searching only (checked aligned); Arabic/Urdu folded (alef forms, yeh, kaf, heh); English by word start. **Bookmarks** with notes (local). **Share** as PNG (RepaintBoundary, pixelRatio 3) via the share sheet.
- **Offline audio:** dart:io HttpClient, 4 at a time, `.part` then rename, 3 tries each, skip existing; resolver plays local files first. Size estimate measured (63 ayahs of Alafasy 128 kbps: 1.6 GB whole). **Morning ayah notification:** own channel `daily_ayah`, ids 0x7f010000+, a week ahead.
- **Unverified on a device:** location permission flow, exact-alarm prayer reminders on your phone, real downloads (speed, storage), silence pauses on Android, the share sheet with a picture.
- **Not built (yet):** bookmarks in sync and backups; Quran settings in backups.
- **Stronger prayer reminders:** titles Salat-ul-Fajr / نمازِ فجر (Jumu'ah on Fridays); tone per reminder through one channel per tone (`prayer_times`, `prayer_alarm` with the phone's alarm sound and alarm audio usage, `prayer_ringtone`, `prayer_vibrate`; sounds by `content://settings/system/...`, nothing bundled); second reminder minutes+seconds after the time (5 s to 59 min 59 s), Fajr only or all, own tone, FLAG_INSISTENT ("keep ringing until opened"); ids 16 a day (0-5 at the time, 8-13 the second); Try it = a test notification in 5 s. **Unverified on a device:** how each tone sounds on your phone, insistent ringing, Do Not Disturb behaviour. Not built: an Azan recording as the tone (needs a recording with a clear licence).

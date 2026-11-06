# Cross-platform validation matrix

A capability is promised to users only when every column it claims is ✅ with evidence. ⬜ = not tested. Updated 2026-11-06.

| Capability | Linux (dev/CI) | Windows | macOS | Android | iOS | Evidence |
|---|---|---|---|---|---|---|
| PDFium render / text / search (engine level) | ✅ | ⬜ | ⬜ | ⬜ | ⬜ | spikes/s1_s2_pdf |
| pdfrx viewer widget, 500 MB PDF, 3000 pages | ⬜ | ⬜ | ⬜ | ⬜ | ⬜ | — |
| Write real PDF annotations (highlight/underline/ink/note) | ✅ | ⬜ | ⬜ | ⬜ | ⬜ | spikes/s1_s2_pdf/evidence |
| Annotated PDF opens correctly in external viewer | ✅ poppler | ⬜ Acrobat/Edge | ⬜ Preview | ⬜ | ⬜ | evidence PNG |
| Encrypted SQLite (sqlite3mc / sqlcipher) + FTS5 | ✅ | ⬜ | ⬜ | ⬜ | ⬜ | spikes/s3_s7_sqlite |
| Drift on encrypted DB, migrations | ⬜ | ⬜ | ⬜ | ⬜ | ⬜ | — |
| Tracker schema query performance @10k | ✅ (container CPU) | ⬜ | ⬜ | ⬜ mid-range device | ⬜ | spikes/RESULTS.md |
| Sync convergence model | ✅ (pure Dart) | n/a | n/a | n/a | n/a | spikes/s4_sync |
| Supabase RLS isolation tests | ⬜ | n/a | n/a | n/a | n/a | — |
| Local notifications (scheduled/recurring) | ⬜ | ⬜ | ⬜ | ⬜ | ⬜ | — |
| Biometric unlock | n/a | ⬜ | ⬜ | ⬜ | ⬜ | — |
| Secure storage | ⬜ | ⬜ | ⬜ | ⬜ | ⬜ | — |
| Encrypted Drift DB + sync service integration tests | ✅ | ⬜ | ⬜ | ⬜ | ⬜ | test/data |
| Sync server SQL: RLS + apply_changes (plain Postgres 16) | ✅ | n/a | n/a | n/a | n/a | supabase/tests |
| Dart reference == Postgres (differential) | ✅ | n/a | n/a | n/a | n/a | packages/sync_engine/tool |
| App shell/auth/lock widget tests | ✅ | ⬜ | ⬜ | ⬜ | ⬜ | test/app |
| App launches with GUI, adaptive layouts visually checked | ⬜ | ⬜ | ⬜ | ⬜ | ⬜ | — |
| Supabase transport/auth against a live project | ⬜ | ⬜ | ⬜ | ⬜ | ⬜ | — |
| Tracker engine (pure Dart) + SQL/reference differential | ✅ | n/a | n/a | n/a | n/a | packages/tracker_engine, test/features/tracker |
| Tracker UI widget tests (grid, board, dialogs, phone layout) | ✅ | ⬜ | ⬜ | ⬜ | ⬜ | test/features/tracker/tracker_ui_test.dart |
| Tracker UI looked at on a real screen / device | ⬜ | ⬜ | ⬜ | ⬜ | ⬜ | — |
| 10k-row tracker performance on a phone | ⬜ | ⬜ | ⬜ | ⬜ | ⬜ | — |
| OCR | ⬜ | ⬜ | ⬜ | ⬜ | ⬜ | — |

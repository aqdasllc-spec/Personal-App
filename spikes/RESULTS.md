# Phase 0 — Spike results

Run on **2026-11-06** in the planning container: **Linux x64 only**, Flutter 3.47.9 / Dart 3.13.7, headless (no GUI, no devices). Anything about Windows, macOS, Android or iOS below is **not tested** and stays open.

| Spike | Verdict (Linux) | Still open |
|---|---|---|
| S-1 pdfrx/PDFium render, text, search | **Partial pass.** PDFium (the engine pdfrx wraps, loaded via `pdfium_dart` 0.4.1) renders, extracts text and finds search matches with per-character bounding boxes. | Not run through the pdfrx *widget* (needs a GUI/device). No large-file test (500 MB / 3000 pages). 4-platform and scroll-FPS/memory checks not done. |
| S-2 write real PDF annotations | **Pass on Linux.** Highlight, underline, ink and text-note annotations created through PDFium FFI; copy saved with `FPDF_SaveAsCopy`; original untouched. `pypdf` reads `/QuadPoints`, `/InkList`, `/Contents`, colours and appearance streams; **poppler** (a different engine) renders all four correctly. | Open the output in Acrobat, macOS Preview, Edge, Chrome. Same code on Windows/macOS/iOS/Android. Free-text box (subtype 3) and strikeout not exercised. Round-trip *import* of existing annotations from third-party PDFs not tested. |
| S-3 encrypted SQLite | **Pass on Linux** for both `sqlite3mc` and `sqlcipher` sources via `hooks: user_defines: sqlite3: source:` in `pubspec.yaml`: encrypted on disk, FTS5 works under encryption, wrong key rejected, second isolate opens it. Documented by the package as available on all native platforms. | Build and run on Win/mac/iOS/Android. Drift on top (not tested). Licences: SQLCipher community & SQLite3MultipleCiphers have their own licences (review in release checklist). Performance cost of encryption not measured. |
| S-4 sync convergence | **Pass (model level).** 5 000 randomized scenarios (1–4 devices, offline periods, clock skew, duplicate deliveries): all devices converge to server state; every overwritten value is causally superseded or in the conflict log. **The test caught a real bug in the first design** (an edit with no known base silently overwrote a server value) — fixed by treating any edit whose base ≠ server's current value as concurrent. | Scalar fields only. Not yet covered: multi-valued set merge, 3-way text merge, delete-vs-edit, relations, real Postgres `apply_changes` RPC + RLS, network/transport. |
| S-5 OCR | **Not started.** | Needs real scan samples and desktop OCR options. |
| S-6 notifications | **Not started.** Needs devices. | |
| S-7 tracker schema benchmark | **Pass at target scale.** See numbers. | Real Drift overhead, real device (mid-range Android) not measured. |

## S-7 numbers (in-memory SQLite 3.54.1, this container's CPU; 20 properties per record)
| Query | 10 000 records (200k cells) p50 / p95 | 100 000 records (2M cells) p50 / p95 |
|---|---|---|
| filter status = X AND progress > 50 | 2.2 / 6.8 ms | 27 / 34 ms |
| sort by progress, page of 50 | 6.5 / 7.9 ms | 77 / 86 ms |
| filter + sort + page of 50 | 1.1 / 1.3 ms | 10 / 17 ms |
| group count by status | 7.9 / 8.7 ms | 107 / 140 ms |
| aggregate avg/sum | 5.8 / 6.3 ms | 69 / 74 ms |
| load page, 50 rows × 8 visible properties | 0.5 / 0.7 ms | 0.5 / 0.7 ms |
| load page, 50 rows × 20 properties | 1.3 / 3.1 ms | 1.1 / 1.7 ms |
| FTS5 MATCH, limit 20 | 6.5 / 8.6 ms | 62 / 63 ms |
| FTS5 index build | 24 ms | 239 ms |
| bulk insert | 200k cells in 0.5 s | 2M cells in 5.4 s |

**Reading:** target (10k records, p95 < 50 ms) is met with a wide margin; paging stays ~1 ms at any size. At 100k records, *unfiltered* full-column sort/group/aggregate drop to 70–140 ms. Mitigations for Phase 2: avoid the join to `records` when no soft-delete filter applies, maintain cached group counts/aggregates per view, and treat >50k-record trackers as a documented soft limit until measured on a device. Benchmarks on an actual phone are an exit criterion for Phase 2.

## Files
`s3_s7_sqlite/` (S-3, S-7) · `s4_sync/` (S-4) · `s1_s2_pdf/` (S-1/S-2; `fixtures/sample.pdf`, `evidence/`). Run with `dart run bin/<file>.dart`. Throwaway spike code — not production.

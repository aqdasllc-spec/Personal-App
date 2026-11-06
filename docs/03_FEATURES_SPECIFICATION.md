# 03 — Features Specification

Status legend: **P1–P7** = roadmap phase (doc 06; Tracker Engine is P2 in the recommended order). ⚠ = depends on a Phase 0 spike. Every requirement has an ID for traceability to tests.

## 1. Feature inventory (by module)
| Module | Features |
|---|---|
| Home | widget grid (add/remove/move/resize/configure), goals progress, active projects, deadlines, today's tasks, week/month overview, recent docs/notes, reading progress, quick capture, stats, custom widgets (tracker view widget, chart widget, saved-search widget) |
| Library | import PDF/EPUB? (see D-10) & documents, shelves/collections, categories/authors/subjects/tags, covers (auto from page 1, custom upload), progress, favorites, recents, history, 3 views, search/filter, drag to shelf |
| Reader | render, nav, thumbnails, TOC, search, zoom, fullscreen, tabs, bookmarks, history, resume position, highlight/underline/strike/ink/sticky/text, colors, annotation manager, export ⚠ |
| Tracker engine | trackers, properties (23 types), records, inline edit, detail panel, views ×7, filters/sorts/groups, formulas, relations, rollups, subtasks, templates, CSV, archive, undo/redo, comments, attachments |
| Goals & projects | goal horizons (long/annual/monthly/weekly), projects, tasks, subtasks, milestones, deadlines, priorities, status, progress, notes, attachments, reminders, dependencies |
| Knowledge | notes, rich text + Markdown, journals, daily notes, tags, categories, backlinks, internal links, linked docs/goals/projects, graph, templates, attachments |
| Planner | day/week/month/year, tasks, events, reminders, recurrence, deadlines, time blocking, goal/project-linked tasks, local notifications |
| Search | books, PDF text, notes, goals, tasks, records, tags, attachment metadata; OCR ⚠; offline |
| AI (optional) | Q&A over PDFs, summarise, key points, notes, tags, goal breakdown, progress summary, discovery, semantic search, relation suggestions |
| Platform | sync, offline, backup/restore, export, auth, MFA, biometrics, notifications |

## 2. Tracker Engine — functional requirements
### 2.1 Table interaction (TR-T)
| ID | Requirement | Acceptance criteria |
|---|---|---|
| TR-T1 | Click a cell to edit inline | Single click selects, Enter/double-click/typing edits; Esc cancels; Tab/Shift-Tab/Enter navigate; commit writes locally < 50 ms and shows no spinner |
| TR-T2 | Typed editors per property | Each type opens its right editor (date picker, option menu, number keypad on mobile…) and rejects invalid input with inline message, never data loss |
| TR-T3 | Resize/reorder columns | Drag handle; width persisted per view; reorder persisted per view; keyboard alternative |
| TR-T4 | Row ops | Add above/below, duplicate (copies cells, optionally subtasks), delete (soft, undoable), reorder by drag (fractional index) |
| TR-T5 | Multi-select & bulk edit | Shift/Cmd/Ctrl click, drag-select range; bulk set value, bulk delete/archive/move; applies in one undoable transaction |
| TR-T6 | Context menus | Right-click (desktop) / long-press (mobile) on row, cell, column header |
| TR-T7 | Copy/paste | TSV ↔ cell ranges; paste into select maps by label; type mismatch is previewed, never silently dropped |
| TR-T8 | Virtualisation | 10k rows × 20 columns scrolls at 60 fps; only visible cells built |
| TR-T9 | Record detail panel | Side panel (desktop) / full screen (mobile): all properties, rich body, subtasks, comments, attachments, relations, history |
| TR-T10 | Undo/redo | ≥ 100 steps per session for cell/row/property/view changes; survives navigation, not app restart |
| TR-T11 | Search within tracker | Matches any visible text; highlights; respects filters |

### 2.2 Property types (TR-P) — config, storage, editing, edge cases
| Type | Configuration | Editing | Edge cases |
|---|---|---|---|
| Text | — | single-line inline | max 10 000 chars; trims control chars |
| Rich text | — | detail panel; inline shows plain preview | stored as Markdown/Delta; sanitised |
| Number | decimals, thousands sep, unit prefix/suffix | numeric field | NaN/inf rejected; locale parsing (`1,5` vs `1.5`) |
| Currency | ISO code, symbol position | numeric | stored as integer minor units; mixed currencies in rollup sum warn |
| Percentage | 0–100 or 0–1 mode | numeric | >100 allowed if configured |
| Checkbox | — | click toggles | tri-state not supported v1 |
| Date | date or datetime, format, timezone mode, reminder | picker, natural text ("next fri") | timezone floating vs fixed; DST |
| Date range | start/end, include time | range picker | end ≥ start enforced; open-ended allowed |
| URL / Email / Phone | — | text + validate | click opens browser/mail/dialer with confirmation; invalid kept but flagged |
| Single select | options{id,label,color}, allow-create | menu; type to create | deleting an option offers re-map; orphan ids shown as "(removed)" |
| Multi-select | same | chips | duplicates removed; order preserved |
| Status | option groups (To-do / In progress / Done), colors | menu | group drives progress/complete logic and Kanban columns |
| Progress bar | manual 0–100 **or** linked to rollup/formula | drag/inline | linked mode read-only |
| People | local contacts list in v1 (no accounts) | chips | becomes real users when sharing (D-9) |
| Files / Images | size & type limits; thumbnail grid | add/drag-drop/camera | virus/type validation; offline pending-upload state; hash de-dupe |
| Relation | target tracker, one/many, two-way | link picker w/ search | can't link across owners; deleted target shows tombstone |
| Rollup | relation, target property, aggregate, filter | read-only | empty relation → 0/blank per aggregate; type-aware formatting |
| Formula | expression, result type | formula editor with autocomplete & live preview | cycles blocked; errors shown as `#ERR` with tooltip; bounded evaluation |
| Created / Last modified | format | read-only | derived from record metadata; not synced as cells |

Property operations: add, rename, change type (with conversion preview and lossy warning; old data kept in a hidden "previous" snapshot for undo), duplicate, hide, delete (soft; restorable for 30 days), set as title.

### 2.3 Views (TR-V)
Table · Kanban (group by select/status; drag between columns updates the property) · Calendar (month/week; date or range property; drag to reschedule) · Timeline (zoomable day→quarter) · Gantt (bars, dependencies via relation, critical path highlight P3+) · Gallery (cover image/first attachment, card properties) · List (compact).
Common: independent filters (nested AND/OR), sorts (multi-key), grouping (collapsible, aggregates per group), visible columns, saved & named, duplicate view, default view per tracker, view-level "lock" to prevent accidental edits.
**Acceptance:** creating/deleting a view never changes records; editing in one view is instantly reflected in all others; deleting the last view is blocked.

### 2.4 Other tracker requirements
Templates (built-in + "save tracker as template"; stored as data; applying creates new IDs), CSV import (column mapping, type inference, preview of first 50 rows, dry-run error report, no partial import without confirmation) and export (current view or all; UTF-8 BOM; formula-injection guard), archive (hidden from views, restorable), comments (Markdown, timestamps), unlimited trackers (soft cap warnings at 500 properties / 100k records per tracker).

## 3. Goals & projects
| ID | Requirement | Acceptance |
|---|---|---|
| GP-1 | Horizons: long-term, annual, monthly, weekly are a *select property* on Goals with a template; custom horizons allowed | Dashboard "this week" filters by it |
| GP-2 | Goal → Projects → Tasks → Subtasks / Milestones via relations & parent_id | Linking a task to a project updates goal progress < 1 s |
| GP-3 | Progress calc configurable: manual / % tasks complete / weighted by effort / milestone-based | Each mode unit-tested with fixtures; changes recompute without data loss |
| GP-4 | Dependencies (blocked-by relation) with Gantt arrows and warning on cycles | Cycle creation rejected |
| GP-5 | Detail pages: header (status, priority, dates, progress ring), tabs for tasks/milestones/notes/files/activity | Same data editable in tracker table |
| GP-6 | Reminders for deadlines (before/at/overdue) | Fires offline on all platforms ⚠ S-6 |
| GP-7 | No fixed workflow: every built-in tracker can be edited or deleted | "Reset to template" available, non-destructive |

## 4. Library & reader
| ID | Requirement | Acceptance / edge cases |
|---|---|---|
| LB-1 | Import files (multi-select, drag-drop on desktop, share-sheet on mobile) | Hash de-dupe prompts "already in library"; unreadable/encrypted PDFs prompt for password; metadata from XMP/info dict; large files streamed with progress; partial import is resumable |
| LB-2 | Shelves/collections, tags, authors, subjects | A book can be in many shelves; bulk move/tag |
| LB-3 | Realistic shelf | 3-D-ish spines (width ∝ pages, colour from cover), selection lifts book, smooth 60 fps with 500 books via lazy rendering; reduce-motion fallback |
| LB-4 | Custom cover | Crop/zoom picker; generated typographic cover if none |
| LB-5 | Progress & history | Last page + scroll offset + zoom restored exactly; reading sessions (start/end/pages) |
| RD-1 | Render & navigate | Continuous & single-page, jump to page, thumbnails sidebar, outline, internal links |
| RD-2 | Search in document | Incremental, highlights all, next/prev, count; scanned pages flagged "no text layer" |
| RD-3 | Tabs | ≥ 10 open docs; background tabs release page caches |
| RD-4 | Annotations | Highlight/underline/strike on selected text; ink with pressure/stylus; sticky note; free text box; 12 colours + custom; undo/redo; per-document annotation list with filter/jump/edit/delete; synced |
| RD-5 | Export annotated PDF ⚠ | Output opens with annotations in ≥ 3 external viewers; original never modified; if only flattened export is possible, UI says "flattened (not editable)" |
| RD-6 | Bookmarks | Page or position; named; listed in side panel |
| RD-7 | Fullscreen/reading mode | Hides chrome; tap/click zones; night (inverted/sepia) page tint |
Edge cases: corrupt PDF, 5 000-page PDF, rotated pages, mixed page sizes, right-to-left text, PDFs with forms (v1: display only), moved/deleted underlying file (re-link flow).

## 5. Knowledge
Notes with Markdown + rich-text toggle; `[[wiki links]]` and `@` mentions to notes, books (with page anchor), goals, projects, records; backlinks panel; daily note auto-created from template; journals with calendar; tags/categories; graph (nodes = notes/books/goals/projects, edges = links & tags; filters, local graph, zoom, 5k nodes via isolate layout + level-of-detail); attachments; note templates with variables (`{{date}}`). Acceptance: renaming a note updates incoming links; deleting leaves broken-link markers, not silent removal.

## 6. Planner
Day (timeline + task list, drag to time-block), week, month, year heatmap; events and tasks; recurrence via RFC 5545 RRULE with exceptions; goal/project-linked tasks (tasks are tracker records, so changes reflect everywhere); reminders with local notifications and snooze; overdue handling; time zones and DST correct (tests around transitions).

## 7. Search
One search box (Ctrl/Cmd-K): typed result groups, filters, recent queries, keyboard navigation, snippets with highlight, "open at page". Offline for all local content; items not downloaded are searchable by metadata only and labelled.

## 8. Cross-cutting
Empty states with a primary action; error messages state *what happened, what is safe, what to do*; undo toasts for destructive actions; every long operation shows progress and can be cancelled.

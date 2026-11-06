# 01 — Project Overview

> **SCOPE CHANGE (2026-11-06, user decision).** The app is now **Home, Library, Planner and Settings** only.
> **Goals & Projects, Knowledge and the custom Tracker Engine were removed** (code, local tables and tests deleted; the full history stays in git). Anything below about trackers, goals/projects, knowledge/notes/graph or the tracker schema is **historical and not planned**. See `docs/07_DECISIONS_AND_RISKS.md` § Scope change and the revised roadmap in `docs/06_ROADMAP_TESTING.md` §1.


> Working title: **Folio** (placeholder — rename freely). Status: **Phase 1 foundation built; Library is next** (see `docs/06_ROADMAP_TESTING.md`).

## 1. Vision
One private, offline-first workspace where a person keeps their **library** (PDFs and documents), **plans their days** (tasks, events, time blocks, reminders) and sees what matters on a **Home** dashboard — on Windows, macOS, Android and iOS, with one shared Flutter codebase.

Visual identity: **Editorial Library + Modern Productivity** — warm paper tones, a serif display face for titles, a clean sans for UI, restrained colour, real depth only where it carries meaning (the bookshelf).

## 2. Who it is for
A single user (v1) with a long-lived personal archive: hundreds of books, thousands of tracker records, years of notes. Multi-user sharing is **out of scope for v1**; the data model reserves `owner_id` and "people" properties so sharing can be added without a rewrite (see decision D-9).

## 3. Platforms
| Platform | Target | UX emphasis |
|---|---|---|
| Windows 10/11 | desktop | sidebar + multi-panel, keyboard-first, large tables, PDF tabs |
| macOS 12+ | desktop | same as Windows, native menu bar |
| Android | phone/tablet | bottom navigation, compact table, quick-capture FAB |
| iOS 15+ | phone/tablet | same as Android, iPad uses split layout |

One responsive layout system with three breakpoints (compact < 600, medium 600–1024, expanded > 1024 dp). Platform-specific code is limited to: file access, notifications, biometrics, secure storage, share sheets.

## 4. Core modules (current scope)
1. **Home** — dashboard: today's tasks, upcoming deadlines, recently opened documents, reading progress, quick capture.
2. **Library** — bookshelves (realistic / grid / list), import, metadata, collections, **PDF reader + annotations**.
3. **Planner** — daily / weekly / monthly / yearly planning, tasks, events, recurrence, time blocking, reminders.
4. **Settings** — account, sync, security (app lock), backup, appearance, rotation, (optional AI later).

Cross-cutting: **Global search** (books, PDF text, tasks), **Sync**, **Backup**, **Security**.

*Removed 2026-11-06:* Goals & Projects, Knowledge, and the custom Tracker Engine.

## 5. Product principles
1. **Your files stay yours.** Original PDFs are never modified; annotations live beside them and export to new files.
2. **Small and focused.** Four sections done well beat a dozen half-built ones.
3. **Offline first, always.** Every create/edit works offline; the network is an optimisation.
4. **Never silently lose data.** Concurrent edits are detected and preserved (conflict log), deletions are soft until purged, backups are independent of sync.
5. **Private by default.** Cloud sync is opt-in at sign-in; AI is off and needs explicit consent per provider and per payload.
6. **Honest scope.** A feature is only marked done when it is implemented *and* tested on the platforms it claims.
7. **Calm interface.** Whitespace, hierarchy, few colours. Motion explains, never decorates.
8. **Fast at scale.** Virtualised lists, indexed queries, background isolates for heavy work.

## 6. Non-goals (v1)
Real-time multi-user collaboration; web client; Linux client (code is portable, but not tested or shipped); an in-app app-store of plugins; server-side PDF processing.

## 7. How the documents fit together
| Doc | Purpose |
|---|---|
| 02 UI/UX | design system, screens, `/design` prototype |
| 03 Features | requirements, workflows, acceptance criteria |
| 04 Architecture | stack, schema, sync, PDF decision, `/architecture` diagrams |
| 05 Security | threat model, encryption, backup, AI privacy |
| 06 Roadmap | phases, spikes, testing, release checklist |
| 07 Decisions & Risks | open decisions requiring your approval (approval gate) |

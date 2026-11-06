# 01 — Project Overview

> Working title: **Folio** (placeholder — rename freely). Status: **planning — awaiting approval. No application code exists yet.**

## 1. Vision
One private, offline-first workspace where a person keeps their **library** (PDFs and documents), builds their own **trackers** (a Notion/Airtable-style database engine), runs **goals and projects**, writes **notes and a knowledge graph**, and **plans their days** — on Windows, macOS, Android and iOS, with one shared Flutter codebase.

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

## 4. Core modules
1. **Home / Command Center** — configurable widget grid.
2. **Library** — bookshelves (realistic / grid / list), import, metadata, collections, **PDF reader + annotations**.
3. **Goals & Projects** — built on the **Tracker Engine**; plus dedicated goal/project detail pages.
4. **Knowledge** — notes, journals, daily notes, backlinks, graph.
5. **Planner** — day/week/month/year, tasks, events, time blocking, reminders.
6. **Settings** — account, sync, security, backup, appearance, AI (off by default).

Cross-cutting: **Tracker Engine** (one reusable database engine), **Global Search**, **Sync**, **Backup**, **Security**, optional **AI**.

## 5. Product principles
1. **User owns the structure.** No hardcoded tracker categories, property names or layouts. Templates are just data.
2. **One engine, many surfaces.** Goals, tasks, reading lists and custom trackers all run on the same record/property/view engine.
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

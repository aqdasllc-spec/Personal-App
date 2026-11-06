# 02 — UI / UX Design

> **SCOPE CHANGE (2026-11-06, user decision).** The app is now **Home, Library, Planner and Settings** only.
> **Goals & Projects, Knowledge and the custom Tracker Engine were removed** (code, local tables and tests deleted; the full history stays in git). Anything below about trackers, goals/projects, knowledge/notes/graph or the tracker schema is **historical and not planned**. See `docs/07_DECISIONS_AND_RISKS.md` § Scope change and the revised roadmap in `docs/06_ROADMAP_TESTING.md` §1.


Interactive concepts: open [`/design/index.html`](../design/index.html) in any browser (theme toggle top-right; tabs for every screen). Rendered PNGs of every screen in **light and dark** are in [`/design/screens`](../design/screens). They are static prototypes with illustrative sample content — not app functionality.

## 1. Design language: "Editorial Library + Modern Productivity"
Warm paper surfaces, ink-black text, one calm accent (**Ink Green**) and one warm secondary (**Brass**) used sparingly. Serif display type for titles and the library; neutral sans for dense UI and tables. Depth is *earned*: shadows appear on books, floating menus and dragged items — flat hairlines everywhere else.

## 2. Tokens
### Colour (semantic; mapped to Flutter `ColorScheme` + `ThemeExtension<FolioColors>`)
| Token | Light | Dark | Use |
|---|---|---|---|
| `bg` | `#F6F2EA` | `#14120F` | app background (paper / ink) |
| `surface` | `#FFFDF8` | `#1C1A16` | cards, panels |
| `surface-2` | `#EFE9DC` | `#25221C` | table header, hover |
| `border` | `#E2D9C8` | `#2F2B24` | hairlines |
| `text` | `#1F1B16` | `#F1EBDD` | primary |
| `text-muted` | `#6F675B` | `#A59C8A` | secondary |
| `accent` | `#2F5D50` | `#7CC1AC` | primary actions, focus |
| `accent-soft` | `#DCE9E3` | `#23382F` | selected rows, chips |
| `brass` | `#B5832A` | `#D9AC4F` | highlights, favourites |
| `danger / warn / ok / info` | `#B3402F / #B7791F / #3C7A4F / #346C9C` | lighter equivalents | status |
Option palette for select/status (10 hues × light/dark pairs, all ≥ 4.5:1 text on chip): gray, brown, orange, yellow, green, teal, blue, purple, pink, red.
Contrast: body text ≥ 7:1, UI text ≥ 4.5:1, borders/graphics ≥ 3:1 — checked in CI via golden + contrast test.

### Typography
Display/titles: **Fraunces** (variable serif, OFL) — 32/40, 24/32, 20/28. UI/body: **Inter** (OFL) — 16/24 body, 14/20 UI, 12/16 caption, tabular numerals in tables. Mono (formulas): **JetBrains Mono**. Fonts are bundled in the app (no runtime download), respect OS text scaling up to 200 %.

### Spacing, shape, motion, elevation
Spacing scale (dp): 2 · 4 · 8 · 12 · 16 · 24 · 32 · 48 · 64. Radius: 6 (inputs/cells) · 10 (cards) · 16 (sheets) · 999 (pills). Elevation: e0 hairline, e1 `0 1 2 /6%`, e2 `0 6 20 /12%` (menus), e3 `0 14 40 /20%` (dialogs, lifted book). Motion: 120 ms (hover/press), 200 ms (panels, menus), 320 ms (page/shelf transitions); easing `cubic-bezier(.2,.8,.2,1)`; **Reduce-motion** replaces transforms with fades.
Density: Comfortable / Compact toggle (row height 40 / 32 dp; mobile min touch 48 dp).

### Icons
One outline icon family, 1.5 px stroke, 20 dp default (Phosphor-style or Lucide, both permissively licensed — final pick at Phase 1). Property types each have a fixed glyph (Aa, #, $, %, ☑, calendar, link, @, ☎, list, tag, ◔ status, bar, person, paperclip, image, ⇄ relation, Σ rollup, ƒ formula).

## 3. Component library (design_system/)
Buttons (primary/secondary/ghost/destructive, icon, split), text field, search field, select, segmented control, tabs (document tabs for reader), chips/pills (status, tag), checkbox/switch/radio, slider, progress bar/ring, avatar, tooltip, toast/undo snackbar, dialog, bottom sheet, popover/context menu, command palette, card (document, record, widget), **data table cell family** (one editor per property type), sidebar/rail/bottom-nav, empty state, skeleton loaders, banner (offline/conflict/backup-overdue).

## 4. Navigation
| Size | Pattern |
|---|---|
| Expanded (>1024) | 240 dp collapsible sidebar (6 sections, trackers & shelves nested), top bar with ⌘K search, sync chip, optional right detail pane |
| Medium (600–1024) | 72 dp icon rail, detail opens as overlay panel |
| Compact (<600) | bottom bar: Home · Library · Goals · Knowledge · Planner; Settings under profile menu; global quick-capture FAB; detail screens are full-screen pushes |
Desktop extras: keyboard shortcuts (⌘/Ctrl-K search, N new, ⌘/Ctrl-Z/Y, ⌘/Ctrl-F, `[` `]` back/forward, Alt-1..6 sections), multi-window-ready panes, menu bar (macOS).

## 5. Screens (see /design)
1. **Home / Command Center** — 12-column widget grid; edit mode shows drag handles/resize corners and a widget gallery; empty state invites adding widgets.
2. **Library** — header (search, filters, view switcher Shelf | Grid | List, sort); **Realistic shelf**: wood-free, paper-toned ledges with soft contact shadows; spines vary in width (page count) and height, colour from cover, serif title rotated; hover lifts 6 dp, selection pulls the book forward and reveals a quick-info card (progress, last read, shelf, actions). Drag a spine onto a shelf label to move.
3. **Reader** — document tabs; collapsible left panel (Thumbnails | Outline | Bookmarks | Annotations); centred page canvas with soft shadow; floating annotation toolbar (select, highlight, underline, strike, pen, note, text, colour, eraser); right panel lists annotations with jump/edit/delete; bottom page slider + zoom; fullscreen hides all chrome; tint modes (paper/sepia/night).
4. **Goals & Projects** — left: tracker list (Goals, Projects, Tasks, custom…) and templates; main: tracker with **view tabs** (Table, Kanban, Calendar, Timeline, Gantt, Gallery, List), toolbar (Filter, Sort, Group, Properties, search, + New); detail pane for the selected record.
5. **Table editor** — spreadsheet: sticky title column, property-type glyph in headers, drag handles, resize grips, row number + checkbox gutter, active cell with inline editor, status pills, progress bars, relation chips, formula cells (read-only tint), bottom summary row (count/sum/avg). Context menu on row/cell/header. Bulk-edit bar appears when multiple rows are selected.
6. **Property editor** — popover/dialog: name, type picker grid with search, type-specific config (options with colour swatches and reorder; number format; formula editor with autocomplete, live preview and error line; relation target; rollup builder), "visible in this view", delete/duplicate. Changing type shows a conversion preview.
7. **Knowledge** — three-pane: tree/tags, editor (Markdown ⇄ rich text), backlinks + properties; graph view with local/global toggle.
8. **Planner** — day timeline with time blocks, task inbox on the left (drag to schedule), week/month/year switchers.
9. **Settings** — Account & MFA, Sync status, Security (biometric lock, auto-lock), Backup (3 mechanisms with last-backup/verify state), Storage, Notifications, Appearance, **AI (off by default, consent flow)**, Data export/deletion.
10. **Mobile** — compact table shows title + 2 chosen properties per row with swipe actions; tap opens full-screen record; horizontal-scroll "full grid" mode; Kanban as paged columns; reader with bottom toolbar.

## 6. Interaction details
- **Inline editing:** no modal per edit; cell shows a 2 px accent focus ring; commit on blur/Enter; error → red ring + helper text, value untouched.
- **Drag & drop:** 4 px threshold, ghost row at e3, drop indicator line in accent; auto-scroll at edges; keyboard alternative (Alt+↑/↓).
- **Selection:** click, Shift-range, Cmd/Ctrl-toggle; rectangular cell range for copy/paste.
- **Feedback:** optimistic UI; undo toast (6 s) for delete/bulk; sync chip changes colour only on problems (calm by default).
- **Empty states:** illustrated line-art + one sentence + primary action ("Import your first book", "Start from a template").
- **Errors:** inline where possible; banners for sync/backup; never raw exceptions.

## 7. Accessibility
Semantic labels for every control, focus order and visible focus, full keyboard operation of the table (arrow navigation, F2 edit), screen-reader announcements for sync/conflict events, 48 dp touch targets, colour never the sole signal (status pills have text/icon), reduce-motion, high-contrast variant of tokens.

## 8. Light & dark
Dark is a designed theme (warm near-black, not pure #000) with the same hierarchy; the bookshelf uses dim ambient lighting; PDF page can stay white or follow tint modes independently of app theme. Theme follows OS by default, with manual override.

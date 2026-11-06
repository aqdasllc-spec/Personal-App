# /design

- `index.html` — interactive high-fidelity concepts (open in a browser; **theme toggle** top-right, tabs for every screen). Uses Google Fonts when online and falls back to system serif/sans offline.
- `screens/<screen>-<light|dark>.png` — rendered screens in both themes: home, library (shelf/grid/list switch inside the HTML), reader, table, kanban, calendar, timeline, gantt, gallery, list, property editor, knowledge, planner, settings, mobile.
- Design tokens and rules: `docs/02_UI_UX_DESIGN.md`. Token values in the prototype's `:root` / `[data-theme=dark]` blocks are the same as the doc.

All content is illustrative sample data. These are **concepts, not functioning software**.

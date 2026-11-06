# Architecture diagrams

All diagrams are [Mermaid](https://mermaid.js.org/) (rendered natively by GitHub). Source of truth for the details is `docs/04_TECHNICAL_ARCHITECTURE.md`. Update both together.

## 1. System context
```mermaid
flowchart LR
  subgraph Device["Device (Windows · macOS · Android · iOS)"]
    UI["Flutter UI<br/>(Riverpod)"]
    DOM["Domain + packages/<br/>tracker_engine · sync_engine"]
    DB[("SQLite (Drift)<br/>+ FTS5, SQLCipher ⚠")]
    FS[("Blob store<br/>content-addressed files")]
    SEC[["Secure storage<br/>keys · tokens"]]
    PDF["pdfrx / PDFium<br/>(isolate)"]
    UI --> DOM --> DB
    DOM --> FS
    UI --> PDF --> FS
    DOM --> SEC
  end
  subgraph Supabase
    AUTH["Auth + MFA"]
    PG[("Postgres + RLS<br/>change_log · audit_log")]
    ST[("Storage (private)<br/>blobs · backups")]
    EF["Edge Functions<br/>scan · delete · export · ai-proxy"]
  end
  AI["AI provider (optional, consented)"]
  DOM <-- "TLS · apply_changes / pull" --> PG
  DOM <-- "TUS resumable · signed URLs" --> ST
  UI --> AUTH
  ST -. webhook .-> EF
  EF --> AI
```

## 2. Layers (per feature)
```mermaid
flowchart TB
  P["presentation (widgets, pages)"] --> A["application (Riverpod notifiers, use cases)"]
  A --> D["domain (entities, repository interfaces, pure Dart)"]
  R["data (repository impls)"] --> D
  R --> L["data/local (Drift DAOs)"]
  R --> C["data/remote (Supabase)"]
  R --> S["data/sync (outbox, pull/push, conflicts)"]
```

## 3. Database ER — tracker engine
```mermaid
erDiagram
  TRACKERS ||--o{ PROPERTIES : defines
  TRACKERS ||--o{ RECORDS : contains
  TRACKERS ||--o{ VIEWS : "saved views (queries)"
  RECORDS  ||--o{ CELLS : "one row per set cell"
  PROPERTIES ||--o{ CELLS : typed_by
  RECORDS  ||--o{ RECORDS : "parent_id (subtasks)"
  PROPERTIES ||--o{ RECORD_LINKS : "relation property"
  RECORDS  ||--o{ RECORD_LINKS : from
  RECORDS  ||--o{ RECORD_LINKS : to
  RECORDS  ||--o{ COMMENTS : has
  RECORDS  ||--o{ ATTACHMENTS : has
  RECORDS  ||--o{ REMINDERS : has
  TRACKERS { uuid id PK
    text name
    text template_id
    ts archived_at }
  PROPERTIES { uuid id PK
    uuid tracker_id FK
    text type
    json config_json
    text sort_key }
  RECORDS { uuid id PK
    uuid tracker_id FK
    uuid parent_id FK
    text sort_key
    text hlc }
  CELLS { uuid record_id PK
    uuid property_id PK
    text v_text
    real v_num
    int v_int
    json v_json
    text hlc }
  RECORD_LINKS { uuid id PK
    uuid relation_property_id FK
    uuid from_record_id FK
    uuid to_record_id FK }
  VIEWS { uuid id PK
    uuid tracker_id FK
    text layout
    json config_json }
```

## 4. Database ER — other domains
```mermaid
erDiagram
  DOCUMENTS ||--o{ SHELF_ITEMS : placed_in
  SHELVES ||--o{ SHELF_ITEMS : holds
  DOCUMENTS ||--o{ ANNOTATIONS : has
  DOCUMENTS ||--o{ BOOKMARKS : has
  DOCUMENTS ||--o{ READING_SESSIONS : logs
  DOCUMENTS ||--o{ DOC_TEXT_PAGES : "extracted/OCR text"
  NOTES ||--o{ NOTE_LINKS : "links out"
  NOTE_LINKS }o--|| ENTITY : "target (note|document|record|goal)"
  TAGS ||--o{ TAGGINGS : used_by
  DASHBOARD_LAYOUTS ||--o{ DASHBOARD_WIDGETS : contains
  SYNC_OUTBOX }o--|| ENTITY : "pending change"
  CONFLICTS }o--|| ENTITY : "preserved losing value"
```

## 5. Tracker engine (query & compute pipeline)
```mermaid
flowchart LR
  V["View config<br/>filters · sorts · group · columns"] --> Q["Query planner<br/>(Dart → SQL on cells + indexes)"]
  Q --> DB[("cells / records / record_links")]
  DB --> PG["Page of record ids<br/>(keyset pagination)"]
  PG --> LOAD["Batch load cells<br/>WHERE record_id IN (…)"]
  LOAD --> CMP["Computed layer<br/>formulas · rollups · created/edited"]
  CMP --> CACHE[("computed_cache (local only)")]
  CMP --> UI["Virtualised TableView / Kanban / Calendar / Timeline / Gantt / Gallery / List"]
  UI -- "inline edit" --> W["Write: cell upsert + hlc + outbox (1 txn)"] --> DB
```

## 6. Sync flow
```mermaid
sequenceDiagram
  participant U as User
  participant L as Local DB
  participant O as Outbox
  participant S as Sync worker (isolate)
  participant P as Supabase (RPC + change_log)
  U->>L: edit cell (offline OK)
  L->>O: txn: write + bump HLC + enqueue
  Note over S: connectivity / resume / timer
  S->>P: apply_changes(batch, device_id, change_ids)
  P-->>S: accepted + conflicts + new seq
  S->>L: mark synced, store conflicts
  S->>P: pull change_log where seq > cursor
  P-->>S: remote changes
  S->>L: merge (field-level rules), recompute caches
  L-->>U: reactive streams update UI, sync chip
```

## 7. Conflict resolution
```mermaid
flowchart TD
  A["Incoming remote change for field F"] --> B{"Local pending change<br/>on same field since base?"}
  B -- no --> APPLY["Apply remote"]
  B -- yes --> T{"Field type"}
  T -- "scalar" --> LWW["Winner = higher HLC<br/>loser saved to conflicts"]
  T -- "long text / note" --> M3["3-way merge on base"]
  M3 -- "clean" --> OK["Apply merged"]
  M3 -- "overlap" --> COPY["Keep both versions → user resolves"]
  T -- "multi-valued" --> SET["Set merge: add-wins, tombstones<br/>log element conflicts"]
  T -- "delete vs edit" --> UND["Edit wins, un-delete + notice"]
  LWW --> BADGE["Non-blocking 'Review' badge + one-tap restore"]
  COPY --> BADGE
```

## 8. Backup & restore
```mermaid
flowchart LR
  subgraph Backup
    SN["VACUUM INTO snapshot"] --> PK["Pack: manifest + db + blobs + checksums"] --> EN["AES-256-GCM (Argon2id key)"]
    EN --> LB["Local folder"]
    EN --> CB["Cloud 'backups' bucket (TUS)"]
    EN --> MX["Manual export file"]
  end
  subgraph Restore
    IN["Select archive"] --> VF["Verify auth tag + checksums + schema ver"] --> PV["Preview counts/dates"] --> PS["Pre-restore snapshot"] --> TD["Restore to temp DB"] --> IC["integrity_check + FK check"] --> SW["Atomic swap + rebuild FTS"]
  end
```

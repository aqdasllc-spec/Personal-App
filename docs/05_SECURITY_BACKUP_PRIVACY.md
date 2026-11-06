# 05 — Security, Backup & Privacy

Reference standard: [OWASP MASVS](https://mas.owasp.org/MASVS/) (STORAGE, CRYPTO, AUTH, NETWORK, PLATFORM, CODE, RESILIENCE, PRIVACY). Target: **MASVS-L1 fully, L2 for STORAGE/CRYPTO/AUTH**; RESILIENCE (obfuscation, root detection) is *not* a goal — a personal app should not block users on rooted devices.

## 1. Assets
Documents and annotations; notes/journals (highly personal); tracker data (finances, health); credentials/session tokens; encryption keys; AI provider keys; backups.

## 2. Threat model (STRIDE-oriented)
| # | Threat | Vector | Mitigation |
|---|---|---|---|
| T1 | Lost/stolen unlocked-then-locked device | physical | App lock (biometric + PIN fallback) with auto-lock timeout; DB encryption ⚠ (SQLCipher, else OS FDE + key in secure store); blobs encrypted at rest; screenshots/app-switcher blur option |
| T2 | Account takeover | credential stuffing, phishing | Strong password policy, breached-password check, optional TOTP MFA, email alerts on new device, session list + remote sign-out |
| T3 | Cross-user data access | RLS bug, IDOR | RLS on every table/bucket; policy tests in CI against a real Postgres (try to read another user's rows with a second JWT); no service-role key in client |
| T4 | Network interception | MITM | TLS only; no cleartext (Android network-security-config, iOS ATS); certificate pinning *not* default (rotation risk) — optional, documented |
| T5 | Malicious file upload/import | PDF/Office exploit, zip bomb | Allow-list by magic bytes + extension, size caps, PDFium (memory-safe-hardened, sandboxed in isolate), no macro execution, never auto-open external links without confirmation; cloud-side scan (below) |
| T6 | Injection | SQL, formula, CSV | Drift parameterised queries only; formula language has **no I/O, no eval**, bounded step count + recursion depth; CSV export prefixes cells starting `= + - @` to prevent spreadsheet formula injection |
| T7 | Secret leakage | keys in app bundle/logs | Only anon key + URL in app; AI keys server-side or secure-storage; logging scrubber; crash reports opt-in and redacted |
| T8 | Malicious backup file | tampered restore | Authenticated encryption (AES-GCM) + manifest checksums verified **before** touching live data; restore into a temp DB, validate schema/version, then swap |
| T9 | Sync tampering / replay | forged changes | JWT-bound RPC, idempotency keys, server-side shape validation, size limits, rate limits |
| T10 | Data exfil via AI | silent upload | AI off by default; per-provider consent; per-request preview of exactly what is sent; local audit of AI calls |
| T11 | Clipboard / share-sheet leaks | platform | No sensitive auto-copy; Android `FLAG_SECURE` option for reader |
| T12 | Supply chain | compromised pub package | Minimal deps, pinned versions + lockfile, `dart pub outdated`/OSV scan in CI, review native-asset build hooks (sqlite3 v3, pdfium) |
| T13 | Denial of service via huge file/tracker | resource | Size limits, streaming parsing, isolates with timeouts |

## 3. Authentication & session
Supabase Auth: email/password (+ optional OAuth), email verification, **TOTP MFA** ([docs](https://supabase.com/docs/guides/auth/auth-mfa)). Access token short-lived; refresh token and DB key material in `flutter_secure_storage` (Keychain `first_unlock_this_device`, Android Keystore-backed EncryptedSharedPreferences/AES, Windows credential store; macOS Keychain). **Biometric unlock** via `local_auth` unlocks a locally stored key-encryption-key; it gates the UI and DB key release, not the Supabase session. Offline use never requires re-authentication beyond the local lock. Local-only mode (no account) is supported.

## 4. Encryption
| Data | At rest | In transit |
|---|---|---|
| SQLite DB | SQLCipher ⚠ (spike S-3) with random 256-bit key held in secure storage; fallback documented in 04 | n/a |
| Local blobs (PDFs/attachments) | OS file protection by default; optional "encrypt library" using per-file AES-256-GCM (XChaCha20 alternative) — trade-off: PDF streaming/seek cost, so default OFF for large PDFs, ON for attachments marked sensitive (D-8) | TLS 1.2+ |
| Cloud DB/storage | Supabase-managed encryption at rest | TLS |
| Backups / exports | **AES-256-GCM**, key = Argon2id(passphrase, salt) → HKDF; format versioned | n/a |
| Optional E2EE for cloud (future) | Not in v1. Note: with E2EE, server-side search/AI/scan are impossible; revisit via D-8 | |

## 5. Storage permissions
Request lazily with purpose strings: file picker (scoped/SAF on Android, security-scoped bookmarks on iOS/macOS), notifications (Android 13+ runtime permission, iOS prompt; Windows/macOS per OS), biometrics (iOS `NSFaceIDUsageDescription`), no broad storage or contacts access, no background location. Android backup: `allowBackup=false` for DB/key files (we manage backups ourselves).

## 6. Cloud security checklist
RLS on all tables, `storage.objects` policies by uid prefix, private buckets, signed URLs (≤ 5 min for viewing, ≤ 1 h for downloads), `audit_log` (sign-in, MFA changes, export, deletion, backup restore, AI enabled/disabled, bulk delete) append-only with RLS read-own, input validation in `apply_changes`, per-user storage quota, Edge-Function rate limiting.
**Malware-scan strategy:** client checks type/size; Storage webhook → `scan-upload` Edge Function forwards new objects to a scanner (ClamAV service or VirusTotal-class API); objects stay `quarantined` (not issued signed URLs) until `clean`; infected objects deleted and user notified. Local imports rely on PDFium isolation + type validation (no scanner on-device in v1).

## 7. AI privacy
- **Disabled by default**; a global kill-switch removes all AI UI and blocks the gateway.
- Enabling requires: choose provider/model → read **"What is sent"** screen (selected text/pages/note titles, never whole library unless chosen; metadata listed) → consent recorded (timestamp, provider, scope) in `audit_log`.
- **Per-action preview** ("Send these 12 pages to <provider>?") with Cancel; remember-choice only per document, revocable.
- Keys: server-side in Edge Function secrets by default; "bring-your-own-key" stored in secure storage, never in source/bundle/logs.
- Semantic search embeddings: local model if feasible (D-6/Phase 6), else provider call under the same consent flow; embeddings are treated as personal data (included in export/deletion).
- Provider data-retention disclosure shown in the consent screen; link to the provider's policy.

## 8. Backup & restore
Sync is **not** backup (a bad edit or delete syncs everywhere), so three independent mechanisms:
1. **Local backup:** scheduled (daily/weekly) + before every migration/restore: SQLite `VACUUM INTO` consistent snapshot + blob manifest → `.folio-backup` (zip: `manifest.json`, `db.sqlite`, `blobs/…` optional, `checksums`), encrypted if a passphrase is set. Destination: app folder or user-chosen folder (desktop; Android SAF; iOS Files/iCloud Drive). Rotation: keep last N.
2. **Cloud backup:** same archive format uploaded to the private `backups` bucket via resumable upload; versions retained (default 5); separate from live sync rows so a sync bug cannot corrupt it.
3. **Manual encrypted export:** user-initiated; choose scope (everything / library only / structured data only / attachments), format `.folio-backup` plus human-readable exports (CSV per tracker, Markdown per note, annotations JSON, annotated PDFs).

**Restore:** pick archive → verify signature/checksums and schema version → preview contents (counts, dates) → choose *replace* or *merge as new workspace* → auto-snapshot of current state → restore into temp DB → integrity check (`PRAGMA integrity_check`, FK check) → atomic swap → rebuild FTS/caches → mark all rows dirty for sync **as a conflict-aware merge**, never silently overwriting newer cloud data (user sees a diff summary).
**Status UI:** last backup date per mechanism, size, verification result (periodic background *verify*: re-read archive, check hashes; monthly *test-restore* into temp DB), warnings if > 7 days old.
**Testing:** see doc 06 §5.

## 9. Data export & account deletion
- **Export (GDPR-style portability):** one tap → ZIP with JSON/CSV/Markdown/original files + `README`. Large exports run in background, resumable.
- **Account deletion:** in-app flow with re-authentication → `delete-account` Edge Function removes Postgres rows, Storage objects, auth user, backups; confirmation email; a short (default 14-day) recovery window optional; local data wipe offered separately. Audit entry kept without content for abuse prevention only.
- **Local-only wipe** ("erase this device"): deletes DB, blobs, keys.

## 10. Secure development practices
Dependency pinning + OSV scan, `flutter analyze` with strict lints, secret scanning in CI, RLS tests, MASVS checklist walkthrough before each release (doc 06 §7), security review in Phase 7 (threat model re-run), responsible-disclosure contact in Settings → About.

## 11. Security decisions log
| ID | Decision | Status |
|---|---|---|
| S-D1 | No E2EE in v1 (keeps scan/search/AI possible) | **Needs your approval (D-8)** |
| S-D2 | SQLCipher at-rest DB encryption | Pending spike S-3 |
| S-D3 | No certificate pinning by default | Proposed |
| S-D4 | AI keys server-side by default | Proposed |
| S-D5 | Backups AES-256-GCM + Argon2id | Proposed |

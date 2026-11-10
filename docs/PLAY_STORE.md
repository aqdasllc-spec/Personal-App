# Publishing Folio on Google Play

This is the checklist for putting Folio on the Play Store, with the answers Play Console asks for. Nothing here
contains a password or key; the signing files stay outside the repository (see DEVELOPMENT.md).

## 1. The bundle

Play takes an **app bundle** (`.aab`), not an APK. Build it with the same signing key as the APKs:

```bash
FOLIO_KEY_PROPERTIES=~/folio-signing/key.properties flutter build appbundle --release \
  --dart-define=SUPABASE_URL=https://<ref>.supabase.co --dart-define=SUPABASE_PUBLISHABLE_KEY=<publishable key>
```

The file is `build/app/outputs/bundle/release/app-release.aab`. Raise the build number in `pubspec.yaml`
(`version: 1.0.0+N`) for every upload; Play refuses a number it has seen.

## 2. Signing: keep the APK and the Play app interchangeable

When Play App Signing asks how to sign, choose **"Use a key from Java keystore"** and upload the existing
`folio-release.jks` key (Play gives a small tool, PEPK, that encrypts it for upload). Then the copy from Play and
the APKs you install yourself are signed alike and update each other. If you let Google create a new key instead,
an APK installed by hand and the Play version cannot replace each other (Android refuses: "App not installed").

## 3. Store listing (draft)

- **Name:** Folio: Library, Planner & Quran
- **Short description (80 characters):** Your PDF library, daily planner, and the Quran with prayer times, in one place.
- **Full description:**
  Folio keeps your books, your day and your prayers together.
  - Library: add PDFs (or open them from other apps), shelves, tags, highlights, notes, pen drawings, chapters,
    instant search inside every book, read aloud, scanned pages made searchable.
  - Planner: tasks and events with reminders, today at a glance, reading goals and streaks.
  - The Quran: Arabic (Uthmani) with Urdu and English translations, 14 reciters, listen offline, Tilawat mode that
    scrolls by itself, tafsir (Ibn Kathir, Bayan-ul-Quran, Ma'ariful Qur'an), search, bookmarks, khatm and hifz plans,
    morning and evening adhkar, the ayah and hadith of the day.
  - Prayer: times for your place, reminders that say the prayer's name (or play your Azan), a "get up" reminder,
    Qibla compass, prayer log and qaza, a home-screen widget.
  - Private: everything stays on your phone; optional sync to your own account; encrypted backups.
- **Category:** Books & Reference (or Lifestyle). **Tags:** Quran, prayer times, PDF reader.
- **Screenshots:** at least 2 phone screenshots (Home with the Quran cabinet, the Library, the Quran reader,
  Prayer times). A 1024×500 feature graphic and a 512×512 icon.

## 4. Permissions Play will ask about

| Permission | Why Folio needs it (text for the declaration form) |
|---|---|
| `USE_EXACT_ALARM` | Prayer-time reminders must come at the exact minute of each prayer; the app works as an alarm clock for the five daily prayers (and a second "get up" alarm the user sets). This is core functionality. |
| `USE_FULL_SCREEN_INTENT` | The prayer alarm shows a full-screen "I'm up" screen, like an alarm clock, so the user can stop it. Only used for alarms the user turned on. |
| `FOREGROUND_SERVICE_MEDIA_PLAYBACK` | Playing Quran recitation with the screen off (with lock-screen controls), and sounding the prayer alarm until the user stops it. |
| `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` | Some phones hold back alarms of apps under battery optimisation, so prayer alarms came late or not at all. The user is asked once, from the prayer reminders card, with an explanation; the app works without it. |
| `ACCESS_COARSE_LOCATION` | To calculate prayer times and the Qibla direction for where the user is. Only when the user taps "Use my location"; the place can also be typed. The location stays on the phone. |
| `POST_NOTIFICATIONS`, `RECEIVE_BOOT_COMPLETED`, `VIBRATE`, `WAKE_LOCK` | Reminders (planner, prayer, ayah of the day), kept after a restart. |
| `USE_BIOMETRIC` | The optional app lock. |

`READ_EXTERNAL_STORAGE` is removed on purpose: files are chosen with the system picker and copied into the app.

## 5. Data safety form

- **Data collected:** only if the user signs in to sync: email address (account), and the user's own content
  (books, notes, tasks, settings), stored in the user's own Supabase project and used only to sync between their
  devices. Not shared with anyone, not used for ads or analytics. Encrypted in transit (HTTPS).
- **Location:** approximate location is used on the device only (prayer times, Qibla); it is **not collected**
  (never sent anywhere).
- **Users can delete their data:** yes (remove books / sign out / delete the account's data from the project).
- **No ads, no analytics, no tracking.**

## 6. Privacy policy (draft; publish it at a public web address, e.g. a GitHub Pages page)

> **Folio privacy policy.** Folio keeps your books, notes, tasks and settings on your phone. If you choose to sign
> in, they are copied to your own cloud storage so your devices stay in step; nobody else can read them. Folio uses
> your approximate location only on your phone, to work out prayer times and the Qibla, and only after you ask it
> to. Quran recitation and tafsir are downloaded from public sources (cdn.islamic.network, and the Tafsir API on
> GitHub / jsDelivr) without sending anything about you. There are no ads, no analytics and no tracking. Contact:
> (your email).

## 7. Content and audience

- Content rating questionnaire: reference / religious texts, no violence, no user-to-user content → rated for everyone.
- Target audience: 13+ (no features aimed at children).
- News app: no. Government app: no. Financial features: none.

## 8. Before each release

1. All tests pass (`flutter test`), `flutter analyze` is clean.
2. Build number raised; bundle built with the release key (§1); check it with
   `jarsigner -verify -verbose build/app/outputs/bundle/release/app-release.aab`.
3. Upload to an **internal testing** track first, install from Play on your phone, check prayer alarms, then promote.

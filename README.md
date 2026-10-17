# Hishab — Voice-First Personal Finance Manager

A **local-first, offline-first** personal finance manager for Android, built for
Bangladesh and priced in **BDT (৳)**. Its differentiator is voice transaction
entry: you speak a transaction in **Bangla, Banglish or English**, the app turns
it into a structured, reviewable draft, and *nothing is ever saved until you
confirm it*.

> **Money in this app is never a floating-point number.** Every amount is an
> integer count of **poisha** (1 BDT = 100 poisha), from the database up through
> the UI.

---

## Table of contents

1. [Highlights](#highlights)
2. [Screens & navigation](#screens--navigation)
3. [Architecture](#architecture)
4. [Data model, schema & migrations](#data-model-schema--migrations)
5. [Money handling](#money-handling)
6. [The voice pipeline](#the-voice-pipeline)
7. [Configuring online interpretation (optional)](#configuring-online-interpretation-optional)
8. [Getting started (build & run)](#getting-started-build--run)
9. [Running the tests](#running-the-tests)
10. [Dependency notes](#dependency-notes)
11. [Security & privacy](#security--privacy)
12. [Implemented features](#implemented-features)
13. [Tested workflows](#tested-workflows)
14. [Known limitations & assumptions](#known-limitations--assumptions)
15. [Building an APK](#building-an-apk)

---

## Highlights

- 🎙️ **Voice entry in three languages.** Bengali script (`বিকাশে ২৫০ টাকা বাজার`),
  Banglish (`bKash e 300 taka bazar`), and English (`spent 180 on groceries
  cash`) all parse to the same internal draft.
- 🔢 **Real Bengali number understanding.** `দেড় হাজার` → 1,500, `আড়াইশো` → 250,
  `দুই হাজার পাঁচশো` → 2,500, `2.5 hajar` → 2,500, `1.5k` → 1,500.
- 🧾 **Never saves something ambiguous.** Missing wallet, unclear direction, or
  two plausible categories all surface for correction; the Save button stays
  disabled until the draft is complete.
- ↩️ **Undo after save.** Every voice save keeps a one-step undo.
- 🔁 **Duplicates are detected, not silently blocked.** A save that matches an
  existing transaction (same type, amount, wallet, within 10 minutes) asks you
  to confirm it isn't a double-tap before writing.
- 🔁 **Transfers are one record.** A transfer is a single logical row
  (source → destination) and is *never* counted as income or expense.
- 🔒 **Local-first.** Everything works offline. The SQLite database never leaves
  the device. Optional "online interpretation" sends *text* (never audio) to an
  endpoint **you** control.
- 🧮 **Derived balances.** Wallet balances are always `opening balance + Σ
  transactions`; opening-balance changes are written to an audit log.
- 🔐 **PIN + biometric app lock**, backed by the Android Keystore.
- 📊 **Budgets, reports, goals, recurring rules, reminders, loans, tags, CSV
  export, versioned JSON backup/restore (optionally AES-256-GCM encrypted).**

---

## Screens & navigation

Bottom navigation shell: **Dashboard · History · Voice · More**, with full-screen
routes pushed on top.

```
/onboarding                     first-run wallet + defaults
/                               Dashboard (monthly summary, recent activity)
/history                        Filterable transaction list (search, range, type, wallet, category, sort)
/voice                          Voice capture + confirmation + undo
/more                           Hub for everything else
/budgets                        Budget list + progress
/reports                        Income vs expense, category breakdown, trend, wallet balances
/wallets  /wallets/new  /wallets/:id
/categories  /categories/new
/transactions/new  /transactions/:id
/goals  /goals/:id
/recurring  /recurring/new
/reminders  /reminders/new
/loans  /loans/:id
/settings  /settings/voice  /settings/security  /settings/data  /settings/audit
```

The app chrome is English. `MaterialApp` supports `en`/`bn` and reads a
`languageCode` setting, but no in-app control currently changes it (it defaults
to `en`). Bengali transaction text always renders with a proper Bengali font
fallback through the system font stack.

---

## Architecture

A layered architecture with a single composition root. **No globals**: every
dependency is created through a Riverpod provider, which is what makes the whole
app testable by swapping providers (in-memory DB, fake recogniser, fixed clock).

```
lib/
├── main.dart                     conventional Flutter entry point (delegates)
├── app/
│   ├── main.dart                 real bootstrap: runApp(ProviderScope(...))
│   ├── app.dart                  root widget, startup splash/failure, MaterialApp.router
│   ├── providers.dart            the entire DI graph (overridable)
│   ├── router.dart              GoRouter route tree + onboarding redirect
│   ├── startup.dart              one-time seeding + notification/reminder sync
│   ├── app_lock_gate.dart        PIN/biometric gate + auto-lock
│   ├── theme.dart               Material 3 light/dark design system
│   ├── labels.dart               enum → human label mappings
│   └── widgets/app_widgets.dart  reusable UI (cards, async views, dropdowns…)
├── core/
│   ├── constants/               settings keys, secure keys, defaults
│   ├── errors/app_exception.dart sealed exception hierarchy (safe messages)
│   ├── security/                secure store, PIN service, backup crypto
│   └── utils/                   Money, Bengali digits, date helpers, id gen
├── data/
│   ├── local/                   drift tables, AppDatabase, connection, seed data
│   ├── repositories/            10 repositories (one per aggregate)
│   └── services/                 notifications, alerts, backup, CSV, seeding
├── domain/
│   ├── enums.dart               TransactionType, WalletType, …
│   ├── models/                  hand-written immutable models + aggregates
│   └── services/                business logic: TransactionService, ReportService,
│                                BudgetService, GoalService, LoanService,
│                                RecurringService, UndoService
└── features/                    one folder per feature (presentation + logic)
    ├── voice/                   domain parser · application pipeline · UI
    ├── dashboard/ history/ transactions/ wallets/ categories/ budgets/
    └── reports/ goals/ recurring/ reminders/ loans/ settings/ onboarding/ more/
```

**Dependency direction:** `features → domain → data → core`. The
`TransactionService` is the **only** code path that writes to the ledger; every
screen, the voice flow, recurring auto-posting, loan cash movement and goal
contributions all go through it, so validation and invariants live in one place.

### Why hand-written models instead of codegen?

Only `drift_dev` + `build_runner` are used. Models, providers and filters are
written by hand (no `freezed`/`json_serializable`/`riverpod_generator`) to keep
the build fast, the dependency surface small, and — importantly — so a generated
file is never the source of truth for a money rule.

---

## Data model, schema & migrations

**13 tables** (`lib/data/local/tables.dart`), currently at
`schemaVersion = 1`:

| Table | Purpose |
|---|---|
| `wallets` | Accounts (cash, bank, mobile financial service, card, other). Opening balance, archive flag, default-income/default-expense flags. |
| `categories` | Income/expense categories with comma-separated `keywords` used by the voice parser. |
| `transactions` | The ledger. Income / expense / **transfer** (single logical row with `walletId` + `toWalletId`). |
| `budgets` | Amount + period (`weekly`/`monthly`/`yearly`/`custom`) + alert threshold. |
| `budget_alerts` | De-dup log so a threshold notification fires once per budget + period + threshold. |
| `savings_goals` | Target amount, optional linked wallet, completion flag. |
| `goal_contributions` | Explicit contributions (optionally funded by a real transfer). |
| `recurring_rules` | Schedule, interval, `next_due_date`, opt-in `auto_post`. |
| `reminders` | Bill reminders with `reminder_days_before`. |
| `loans` | Lending/borrowing with direction; principal is bookkeeping. |
| `loan_payments` | Repayments against a loan. |
| `app_settings` | Flat key/value store for non-sensitive preferences. |
| `audit_logs` | Append-only trail of opening-balance edits, restores, archives, etc. |

### Integrity enforced in SQL, not just in Dart

- `CHECK (amount_poisha > 0)` — no zero/negative amounts.
- `CHECK ((type = 'transfer' AND to_wallet_id IS NOT NULL AND to_wallet_id <>
  wallet_id) OR (type <> 'transfer' AND to_wallet_id IS NULL))` — a half-transfer
  (or a stray destination on an expense) is impossible.
- `CHECK (type = 'transfer' OR fee_poisha = 0)` — only transfers may carry a fee.
- Foreign keys on **all 14** relations (`ON DELETE RESTRICT / SET NULL /
  CASCADE` chosen per relation). `PRAGMA foreign_keys = ON` is set in
  `beforeOpen`.

> **drift 2.31 caveat.** In drift 2.31 the `.references(...)` builder silently
> emitted no constraint, so every FK here is written as an explicit
> `.customConstraint('... REFERENCES ...')`. You can verify them all at once:
> `grep -c REFERENCES lib/data/local/app_database.g.dart` → `14`.

### Migrations

`MigrationStrategy` is built for **forward-only, stepwise** upgrades: `onCreate`
creates the schema and indices; `onUpgrade` walks one version at a time so every
intermediate state is valid; `beforeOpen` turns foreign keys on for every
connection. Index creation is a single `_createIndices()` step, so adding an
index later means adding it there (idempotent).

Multi-step operations run inside `db.transaction(...)`. Transfers, transfer
deletion (which also removes the linked fee row), restore, and recurring
auto-posting are all atomic — a crash mid-way leaves the database consistent.

---

## Money handling

`lib/core/utils/money.dart` is the single money value object.

- Stored and passed around as **`int` poisha**. Never `double`.
- `Money.tryParse` accepts `৳`, `taka`, thousands separators, Bengali digits
  (`১২৩`), and decimals (`2.5` → 250 poisha).
- Formatting (`money_formatter.dart`) supports **Bangladeshi grouping**
  (`১,০০,০০০` style) and optional Bengali digits.

Reports compute income and expense with SQL `SUM`, and **exclude
`type = 'transfer'`** from both totals, so moving money between your own wallets
can never look like earning or spending.

---

## The voice pipeline

```
 microphone ──▶ SpeechRecognizer ──▶ transcript
                                        │
                     ┌──────────────────┴───────────────────┐
                     ▼                                      ▼
           LocalRuleInterpreter                  OnlineVoiceInterpreter (optional)
           (on-device, always)                   (POSTs the *text* only)
                     │                                      │
                     └──────────────┬───────────────────────┘
                                    ▼
                       mergeHint()  ← strictly additive: online
                                    │   may only fill fields the local
                                    │   parser left empty
                                    ▼
                        VoiceController.interpret()
                                    ▼
                  confirmation form (editable, per-field warnings)
                                    ▼
            TransactionService.create()  ← the only ledger write path
                                    ▼
                      undo (one step) + duplicate prompt
```

### Domain pieces (`lib/features/voice/domain/`)

- **`text_normalizer.dart`** — unifies Bangla/Banglish/English spellings, strips
  recognition punctuation, folds common mis-hearings.
- **`bengali_number_parser.dart`** — the number engine. Handles unit/hundred
  composition (`দুই হাজার পাঁচশো`), scale words, relative fractions (`দেড়` =
  1.5, `আড়াই` = 2.5, `সোয়া` = 1.25), digit suffixes (`1.5k`), and Latin
  spellings from a Banglish transcript (`dher hazar`).
- **`wallet_alias_matcher.dart`** — matches a spoken wallet to a real one via
  name, type word, and known aliases; **refuses to guess** when ambiguous
  (e.g. `নগদ` with both a *Cash* wallet and a *Nagad* wallet present).
- **`category_matcher.dart`** — keyword scoring within the sentence, scoped to
  the transaction kind; flags a tie instead of picking one.
- **`relative_date_parser.dart`** — `আজ`/`গতকাল`/`আজ নয়, গতকাল`, explicit Bengali
  dates, numeric dates; defaults to "no date spoken".
- **`transaction_type_classifier.dart`** — income / expense / transfer / unknown,
  with the rule that a bare amount is **left unresolved** rather than guessed.
- **`voice_transaction_parser.dart`** — composes the above into a
  `ParsedTransaction` with a `confidence` score (0..1), a `unresolved` field set,
  and human-readable warnings, then builds a `TransactionDraft`.

> Confidence is an **internal** signal used to decide which correction prompts to
> show. It is never presented as a recognition-accuracy percentage.

### Application layer (`lib/features/voice/application/`)

- **`SpeechRecognizer`** is a seam; `NativeSpeechRecognizer` wraps
  `speech_to_text`. Tests inject a scripted fake, so the entire flow runs with
  no microphone.
- **`VoiceController`** (Riverpod `Notifier`) drives `idle → listening →
  interpreting → review → saved/error`, runs the optional online interpreter,
  merges its hint additively, and — if the parser could not yet build a draft —
  falls back to a **placeholder draft** so the confirmation form always renders
  (with Save disabled until every problem is fixed).
- **Confirmation** is mandatory. A low-confidence or ambiguous parse can never
  be auto-saved.

---

## Configuring online interpretation (optional)

By default the app is **100% offline** and this section can be ignored.

The app also supports pointing at a *smarter* interpreter that **you** host, to
help with unusual phrasing. Read this carefully — the design has deliberate
limits:

- ✅ On-device speech recognition **always runs first**. The phone turns your
  voice into text locally.
- ✅ Online mode sends **only the transcript text** (plus today's date and your
  wallet/category *names*) to your endpoint.
- ❌ It **never uploads audio**.
- ❌ It is **not** a replacement speech recogniser.
- 🔒 The online result is **strictly additive**: it can only fill fields the
  local parser left empty. It can never override a wallet or amount you actually
  said, so a bad server response cannot silently misfile a transaction.

### Set it up in the app

1. **Settings → Voice entry → Interpretation mode → "Online interpretation"**
   (turns `voiceProviderId` to `cloud`).
2. **Endpoint URL** — e.g. `https://your-server.example/interpret`. It must
   start with `http://` or `https://`.
3. **Language code** — sent with the request (default `bn-BD`).
4. **On-device recognition locale** — e.g. `bn_BD`, `bn_IN`, `en_US`.
5. **API token** — paste your bearer token. It is written **only** to the
   device's secure storage (Android Keystore-backed) and is **never shown again,
   never logged, never written to the database or a backup.**

### Request the app sends

`POST <endpoint>` with `Content-Type: application/json` and, when a token is
saved, `Authorization: Bearer <token>`:

```json
{
  "text": "kal bKash e 300 taka bazar korlam",
  "language": "bn-BD",
  "today": "2026-03-11T10:00:00.000",
  "wallets": ["Cash", "bKash", "City Bank"],
  "categories": ["Groceries", "Transport", "Salary"],
  "schema": { "type": "income | expense | transfer", "amount": "number, in BDT", "wallet": "exact wallet name from the list, or null", "toWallet": "exact wallet name for a transfer destination, or null", "category": "exact category name from the list, or null", "date": "ISO-8601 date/time, or null", "description": "short free text, or null", "confidence": "number between 0 and 1" }
}
```

### Response the app expects

Any of these fields may be omitted or `null`; only fields the local parser
couldn't resolve will be taken:

```json
{
  "type": "expense",
  "amount": 300,
  "wallet": "bKash",
  "toWallet": null,
  "category": "Groceries",
  "date": "2026-03-10T13:00:00.000",
  "description": "bazar",
  "confidence": 0.93
}
```

The app resolves `wallet`/`category` **by exact name** against *your* real data —
the server can never invent a wallet you don't own. Failures (timeout,
unreachable, non-2xx, unreadable body) are surfaced as a non-blocking message and
the on-device result is used instead.

### Notes for operators

- **You can pre-fill the endpoint at build time** (non-secret only) so users
  don't have to type it:
  `--dart-define=PFM_CLOUD_SPEECH_ENDPOINT=https://your-server.example/interpret`
  and optionally `--dart-define=PFM_CLOUD_SPEECH_LANGUAGE=bn-BD`. A value the
  user sets in Settings always wins. Online interpretation still stays off until
  the user enables it. See `.env.example`.
- **Never bake the token into a build.** A `--dart-define` ends up inside the
  APK and is trivially extractable. The token belongs in secure storage, entered
  by the user at runtime.
- The transport is a single `dart:io` `HttpClient` POST — no third-party HTTP
  dependency, and no audio or telemetry is sent.
- TLS: always use `https://` in production.

---

## Getting started (build & run)

### Prerequisites

- **Flutter 3.47+** (Dart 3.13+) — code requires Dart SDK `>=3.10.0`.
- **JDK 17** and **Android SDK** with platform tools + build-tools.
- An Android device or emulator (Android 6.0 / API 23 or newer).

### Toolchain environment

This project was developed against a **locally installed** toolchain. Before any
`flutter`/`dart` command, source the environment script:

```bash
source /home/groot/development/env.sh
```

That script exports `PATH`, `JAVA_HOME`, `ANDROID_SDK_ROOT`, `ANDROID_HOME`,
`PUB_CACHE` and `FLUTTER_ROOT` (see `.env.example` for the variables themselves).
If you use a system-wide Flutter, you can skip it.

### Install, analyse, test, run

```bash
source /home/groot/development/env.sh

flutter pub get

# Generate the drift code (only needed after changing tables/*.dart):
dart run build_runner build --delete-conflicting-outputs

flutter analyze                 # must report: No issues found!
flutter test                    # all suites green

flutter run                     # on a connected device/emulator
flutter build apk --debug       # debug APK
flutter build apk --release     # debug-key-signed release APK
```

The conventional entry point `lib/main.dart` delegates to `lib/app/main.dart`, so
plain `flutter run` / `flutter build apk` work with no extra flags.

### First run

Onboarding asks you to confirm/create your first wallet and pick default
income/expense wallets. Default **categories** and a **Cash** wallet are seeded
once and idempotently (`seed_version` guards against double-seeding on an
existing install).

---

## Running the tests

```bash
source /home/groot/development/env.sh
flutter test
```

**117 tests** across five suites:

| Suite | What it covers |
|---|---|
| `test/unit/money_test.dart` | `Money.parse/format`, integer arithmetic (no float drift), symbol/taka/separator handling. |
| `test/unit/bengali_number_parser_test.dart` | Bengali word-numbers, scale words, fractions, Latin spellings, digit suffixes. |
| `test/unit/voice_matching_test.dart` | Wallet alias matching (incl. the `নগদ` ambiguity), category matching, relative dates. |
| `test/voice/voice_parser_test.dart` | **Versioned parser corpus**: bn/banglish/en sentences, recognition noise, missing/ambiguous wallets, transfers, relative dates, draft construction. |
| `test/integration/ledger_test.dart` | Balance invariants, transfers (incl. fee + delete), validation, duplicate prevention, edit/delete/undo, opening-balance audit, persistence. |
| `test/integration/features_test.dart` | Reports, budgets, goals, loans, recurring, backup round-trip + encryption, CSV export, seeding idempotency. |
| `test/voice/voice_flow_widget_test.dart` | **13 end-to-end widget tests** of the voice flow: mic capture, contextual biasing, empty transcript, engine unavailable + typed fallback, Banglish/English/number/relative-date typed entry, missing-wallet + ambiguous-category can't-save, transfer balances, duplicate "Save it anyway", undo. |

Test infrastructure (`test/helpers/`):

- `test_env.dart` — in-memory drift database
  (`open.overrideFor(OperatingSystem.linux, () => DynamicLibrary.open('libsqlite3.so.0'))`),
  a `SequentialIdGenerator`, a `FixedClock` (fixed at `2026-03-11 10:00`), and
  helpers to seed wallets/categories.
- `fake_speech_recognizer.dart` — a scripted `SpeechRecognizer` for the widget
  tests.

The widget-test harness unmounts the `ProviderScope` *inside* each test body so
drift's stream-query cancellation timers don't trip the "a Timer is still
pending" check, and uses a tall surface so no control is off-screen.

---

## Dependency notes

- **`drift` is pinned to exactly `2.31.0`** (with `drift_dev 2.31.0`,
  `sqlite3 ^2.9.0`, `sqlite3_flutter_libs ^0.5.42`). From drift 2.32 the
  `sqlite3` dependency moves to 3.x, which ships SQLite through Dart **build
  hooks** and requires a host C toolchain (clang) *in addition to* the Android
  NDK. 2.31 + the classic Gradle/CMake plugin is the combination that builds
  reliably here (and on any normal Android build machine). **Do not upgrade
  drift without revisiting this.**
- `flutter_riverpod` 3.x — classic `Notifier`/`Provider` API, manual providers.
- `go_router` for declarative navigation with an onboarding redirect.
- `speech_to_text` for on-device recognition (it requests the microphone
  permission itself, so no `permission_handler` dependency is pulled in).
- `flutter_local_notifications` + `timezone`/`flutter_timezone` for scheduled
  budget/reminder alerts (Android core-library desugaring is enabled for this).
- `flutter_secure_storage` + `local_auth` + `crypto` + `pointycastle` for the
  PIN, biometric gate, and backup encryption.
- `fl_chart` (reports), `share_plus`/`file_picker`/`csv` (export/backup).

---

## Security & privacy

- **No secret is ever shipped.** There is no API key, token, or credential in
  the source, docs, test fixtures, or the APK. The only runtime secret (the
  online-interpretation token) is entered by the user and stored in the platform
  keystore.
- **PIN** is never stored. A random 16-byte salt plus a PBKDF2-HMAC-SHA256
  verifier (**120,000 iterations**) live in secure storage; verification is
  constant-time.
- **Backups** are versioned JSON. Optionally wrapped in an **AES-256-GCM**
  envelope with a **PBKDF2-HMAC-SHA256** key (**150,000 iterations**, random
  16-byte salt, random 12-byte nonce).
- **Audit trail** records *why* a balance changed (opening-balance edits,
  restores, archives) — structured deltas only, never statements.
- **No telemetry, no analytics, no crash reporting, no ads.** The app makes
  network requests only when you explicitly turn on online interpretation.

---

## Implemented features

**Ledger**
- [x] Wallets (cash / bank / MFS / card / other), archive-with-history, opening balances with audit trail, default income/expense wallets.
- [x] Income, expense and **single-record transfers** (with optional fee as a linked real expense row).
- [x] Transaction history: filter by range/type/wallet/category, text search, sort, pagination-friendly queries.
- [x] Edit, delete, and one-step **undo** after save.
- [x] Duplicate detection (same type/amount/wallet within 10 minutes) with an explicit override.
- [x] Categories (income/expense) with keywords, archive, defaults.
- [x] Tags, merchant, counterparty, notes.

**Voice (primary feature)**
- [x] On-device recognition with contextual biasing (your wallet/category names).
- [x] Bengali / Banglish / English parsing, Bengali word-numbers, relative dates.
- [x] Wallet + category resolution that refuses ambiguity; default-wallet policy.
- [x] Mandatory confirmation with per-field warnings; Save disabled while incomplete.
- [x] Optional, additive online interpretation (text only; user-hosted).
- [x] Typed-transcript fallback when the speech engine is unavailable.
- [x] Versioned parser test corpus (bn / banglish / en).

**Money management**
- [x] Budgets (weekly/monthly/yearly/custom) with thresholds and non-repeating notifications.
- [x] Reports: income vs expense, net flow, category breakdown, wallet balances, 6-month trend, budget performance.
- [x] Savings goals + contributions (a contribution from a wallet is a real transfer).
- [x] Recurring rules with explicit schedules; auto-posting is opt-in and idempotent.
- [x] Bill reminders with lead time and scheduled notifications.
- [x] Lending/borrowing with outstanding balances; cash movement is opt-in.
- [x] CSV export (ASCII amounts, currency column) and versioned JSON backup/restore with merge/replace preview and optional encryption.
- [x] PIN + biometric app lock with auto-lock.
- [x] Data clearing with confirmation; audit log viewer.

**Platform**
- [x] Material 3 light/dark theme; optional Bengali digits and Bangladeshi (lakh/crore) grouping.
- [x] Offline/online capability explained in-app.

---

## Tested workflows

These are the workflows exercised by the automated suite (not aspirational
claims):

1. **Spoken Bangla expense** (`বিকাশে ২৫০ টাকা বাজার`) → expense, 25,000 poisha, bKash wallet, Groceries category.
2. **Banglish expense with recognition noise** → correct amount/wallet; date defaults to "today".
3. **English expense** (`spent 180 on groceries cash`) → cash wallet.
4. **Bengali income** (`৩০,০০০ বেতন`) → income, correct wallet.
5. **Number variations** — `দেড় হাজার`=1500, `পাঁচশো`=500, `2.5 hajar`=2500, mis-heard `দের`→1500.
6. **Missing wallet** → parse records amount but flags wallet unresolved; no draft; save blocked.
7. **Ambiguous wallet** (`নগদ` with Cash+Nagad) → refuses to guess.
8. **Transfer** → single transfer draft, source+destination, **no category**, not counted as income/expense.
9. **Relative dates** (`গতকাল দুপুরে`, negated date) → correct day.
10. **No direction** (bare amount) → left unresolved, not guessed.
11. **Duplicate** → first save succeeds; identical second save prompts; "Save it anyway" writes.
12. **Undo** → saved voice transaction is removed and balance restored.
13. **Widget flow** — mic capture, contextual biasing, empty transcript, engine-unavailable + typed fallback, and the type/number/date typed-entry cases all run end-to-end through the real confirmation form.
14. **Balances are derived** from opening balance + transactions; zero-opening wallet starts empty.
15. **Transfer fee** becomes exactly one expense row; deleting the transfer removes the fee.
16. **Validation** rejects same-wallet transfers, kind-mismatched categories, non-positive amounts, and archived-wallet writes — writing nothing.
17. **Archived wallet** keeps its history in reports.
18. **Opening-balance change** writes an audit entry.
19. **Reports** separate income/expense/transfers; **budgets** fire a threshold alert once; **goals** move money as a transfer; **loans** treat principal as bookkeeping unless cash movement is opted in and refuse over-repayment; **recurring** posting is idempotent and "skip" writes nothing but advances the due date.
20. **Backup** round-trips every table, encrypts/decrypts with a password, and rejects non-backup files; **CSV export** writes the expected header/format and stable file names; **seeding** is idempotent.

---

## Known limitations & assumptions

- **Speech quality is the platform's.** Recognition accuracy depends entirely on
  the Android speech engine and the installed language pack. The app does not
  and cannot quote an accuracy number; nothing is saved without confirmation.
- **Banglish is parsed with rules**, not a statistical model. Exotic phrasing may
  be left unresolved for you to fix in the confirmation form.
- **`কাল` is context-dependent.** In Bengali script it maps to *yesterday*; in
  Banglish (`kal`) it also maps to *yesterday*. Genuine "tomorrow" phrasing
  should be stated explicitly.
- **Bengali decimal digits** such as `২.৫` are flattened by the normaliser to
  `২ ৫`; use ASCII `2.5` (or `দেড়`/`আড়াই`) for fractional amounts. ASCII
  decimals work everywhere.
- **Online interpretation** re-reads the text only — it does not improve the
  audio recognition itself, and it requires an endpoint you host and secure.
- **Weekly/custom budgets** rely on the configured start date; there is no
  fiscal-year setting.
- **Loan interest** is not modelled explicitly; the principal is bookkeeping by
  default and any real cash movement is opt-in.
- **Notifications** are best-effort: exact-alarm battery restrictions on some
  OEM Android builds can delay scheduled reminders.
- **Currency is fixed to BDT.** There is no multi-currency support.
- The **release APK is signed with the debug key** so it builds out of the box;
  replace the signing config before publishing.

---

## Building an APK

```bash
source /home/groot/development/env.sh
flutter build apk --debug      # build/app/outputs/flutter-apk/app-debug.apk
flutter build apk --release    # build/app/outputs/flutter-apk/app-release.apk
```

Debug and release differ only by optimisation and the deliberately-temporary
debug signing key (`android/app/build.gradle.kts`). `minSdk` is 23, core-library
desugaring is enabled for the notification plugin, and the app requests only the
microphone permission (plus the standard `POST_NOTIFICATIONS` on API 33+).

---

## Contributing

Contributions are welcome. Please read [`CONTRIBUTING.md`](CONTRIBUTING.md) for
setup, code style and the checks that must pass, and [`SECURITY.md`](SECURITY.md)
before touching security, the backup format or the voice pipeline.

The golden rules: **money is always integer poisha**, and **nothing is ever saved
without an explicit user confirmation**.

## License

Released under the [MIT License](LICENSE). © 2026 Hishab contributors.
